#!/usr/bin/env bash
# Installs agent skills from git repositories into the workspace. Runs on every
# start and is idempotent. See ../README.md for the behaviour in full.
#
# Input: AGENT_SKILLS_CONFIG, base64 of
#   {"managed_settings_dir": "...", "sources": [{name, url, ref, skills, claude_plugin}]}
#
# One failing source never stops the others; problems are logged as WARN and
# the script still exits 0. It exits 1 only when it can't run at all.
set -uo pipefail

log() { printf '[agent-skills] %s\n' "$*"; }
warn() { printf '[agent-skills] WARN: %s\n' "$*"; }

if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
  warn "bash 4.4 or later is required (found $BASH_VERSION)"
  exit 1
fi
for cmd in git jq base64 cp diff find install; do
  command -v "$cmd" >/dev/null 2>&1 || {
    warn "$cmd not found"
    exit 1
  }
done

CONFIG=$(printf '%s' "${AGENT_SKILLS_CONFIG:-}" | base64 -d 2>/dev/null)
if ! jq -e '.sources | type == "array"' >/dev/null 2>&1 <<<"$CONFIG"; then
  warn "AGENT_SKILLS_CONFIG is missing or invalid"
  exit 1
fi

DATA_DIR="$HOME/.local/share/agent-skills"
SRC_DIR="$DATA_DIR/src"
MANIFEST="$DATA_DIR/manifest.json"
AGENTS_SKILLS="$HOME/.agents/skills"
CLAUDE_SKILLS="$HOME/.claude/skills"
MANAGED_DIR=$(jq -r '.managed_settings_dir // "/etc/claude-code/managed-settings.d"' <<<"$CONFIG")
MANAGED_FILE="$MANAGED_DIR/30-agent-skills.json"
SKILL_RE='^[a-z0-9]+(-[a-z0-9]+)*$'
SOURCE_RE='^[a-z0-9][a-z0-9._-]*$'
PLUGIN_RE='^[A-Za-z0-9][A-Za-z0-9._-]*$'

# Never prompt for credentials: a source that needs them fails and is skipped.
# Coder sets GIT_SSH_COMMAND to its own key helper; keep that when it's there.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}"
mkdir -p "$SRC_DIR" "$AGENTS_SKILLS" || {
  warn "can't create $SRC_DIR or $AGENTS_SKILLS"
  exit 1
}

if command -v flock >/dev/null 2>&1; then
  exec 9>"$DATA_DIR/lock"
  flock -n 9 || {
    log "another run is in progress; skipping"
    exit 0
  }
fi

OLD_MANIFEST=$(jq -c 'if type == "object" then . else {} end' "$MANIFEST" 2>/dev/null) || OLD_MANIFEST='{}'
[ -n "$OLD_MANIFEST" ] || OLD_MANIFEST='{}'

tilde() { printf '%s' "${1/#"$HOME"/\~}"; }
first_line() { printf '%s\n' "$1" | sed -n '/[^[:space:]]/{p;q;}'; }

run_git() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 300 git "$@"
  else
    git "$@"
  fi
}

# checkout_ref DIR REF: shallow-fetch REF (a tag, branch or commit) from origin
# and check it out, discarding local changes. Prints git's errors.
checkout_ref() {
  run_git -C "$1" fetch --quiet --depth 1 --force --no-tags origin "$2" 2>&1 &&
    git -C "$1" -c advice.detachedHead=false checkout --quiet --force --detach 'FETCH_HEAD^{commit}' 2>&1 &&
    git -C "$1" clean -qffdx 2>&1
}

# sync_source NAME URL REF: bring $SRC_DIR/NAME to URL at REF. Returns 0 when a
# checkout is available (fresh, or the previous one after a failed fetch).
sync_source() {
  local name=$1 url=$2 ref=$3 dir="$SRC_DIR/$1" tmp err cur_url="" cur_ref=""
  if [ -d "$dir/.git" ]; then
    cur_url=$(git -C "$dir" config --get remote.origin.url 2>/dev/null)
    cur_ref=$(git -C "$dir" config --get agent-skills.ref 2>/dev/null)
  fi
  if [ -d "$dir/.git" ] && [ "$cur_url" = "$url" ]; then
    if err=$(checkout_ref "$dir" "$ref"); then
      git -C "$dir" config agent-skills.ref "$ref"
      return 0
    fi
    warn "$name: can't fetch $ref from $url ($(first_line "$err")); keeping the previous checkout ($cur_ref)"
    return 0
  fi
  # New source, or its URL changed: clone beside the old checkout and swap.
  tmp="$SRC_DIR/.new-$name"
  rm -rf "$tmp"
  if err=$(git init --quiet "$tmp" 2>&1 && git -C "$tmp" remote add origin "$url" 2>&1 && checkout_ref "$tmp" "$ref"); then
    git -C "$tmp" config agent-skills.ref "$ref"
    rm -rf "$dir" && mv "$tmp" "$dir" && return 0
    warn "$name: can't replace $dir"
  else
    warn "$name: can't fetch $ref from $url ($(first_line "$err"))"
  fi
  rm -rf "$tmp"
  if [ -d "$dir/.git" ]; then
    warn "$name: keeping the previous checkout ($cur_url at $cur_ref)"
    return 0
  fi
  return 1
}

# The `name:` from SKILL.md's front matter, if any.
frontmatter_name() {
  awk 'NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
       /^---[[:space:]]*$/ { exit }
       /^name:/ { sub(/^name:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); gsub(/^["\047]|["\047]$/, ""); print; exit }' "$1"
}

# Skill directories in a checkout, relative to it ("" for the root), skipping
# hidden paths and skills nested inside another skill.
list_skill_dirs() {
  local rel kept=() k nested
  while IFS= read -r rel; do
    nested=0
    for k in "${kept[@]}"; do
      if [ -z "$k" ] || [[ $rel == "$k"/* ]]; then
        nested=1
        break
      fi
    done
    [ "$nested" = 1 ] && continue
    kept+=("$rel")
    printf '%s\n' "$rel"
  done < <(cd "$1" && find . -name '.?*' -prune -o -type f -name SKILL.md -print |
    sed -e 's|^\./||' -e 's|SKILL\.md$||' -e 's|/$||' | LC_ALL=C sort)
}

declare -A WANT_AGENTS=() WANT_CLAUDE=() FAILED=() CONFIGURED=() MARKETPLACE_OF=()
ORDER_AGENTS=()
ORDER_CLAUDE=()
CLAUDE_SETTINGS='{}'

count=$(jq '.sources | length' <<<"$CONFIG")
for ((i = 0; i < count; i++)); do
  src=$(jq -c ".sources[$i]" <<<"$CONFIG")
  name=$(jq -r '.name // ""' <<<"$src")
  url=$(jq -r '.url // ""' <<<"$src")
  ref=$(jq -r '.ref // ""' <<<"$src")
  claude_plugin=$(jq -r 'if .claude_plugin == false then "false" else "true" end' <<<"$src")
  mapfile -t filter < <(jq -r '(.skills // ["*"])[]' <<<"$src")
  [ "${#filter[@]}" -gt 0 ] || filter=("*")

  if ! [[ $name =~ $SOURCE_RE ]] || [ -z "$url" ] || [ -z "$ref" ]; then
    warn "source $((i + 1)): needs a valid name, url and ref; skipping"
    continue
  fi
  if [ -n "${CONFIGURED[$name]+x}" ]; then
    warn "$name: listed twice; using the first"
    continue
  fi
  CONFIGURED[$name]=1

  if ! sync_source "$name" "$url" "$ref"; then
    FAILED[$name]=1
    continue
  fi
  dir="$SRC_DIR/$name"
  used_ref=$(git -C "$dir" config --get agent-skills.ref 2>/dev/null)
  commit=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)

  # Claude Code: register the repo's marketplace, or fall back to copying.
  to_claude=1
  plugin_note=""
  mp="$dir/.claude-plugin/marketplace.json"
  if [ "$claude_plugin" = true ] && [ -f "$mp" ]; then
    mname=$(jq -r '.name // "" | strings' "$mp" 2>/dev/null)
    mapfile -t plugins < <(jq -r '.plugins[]?.name // empty | strings' "$mp" 2>/dev/null)
    bad=0
    for p in "${plugins[@]}"; do [[ $p =~ $PLUGIN_RE ]] || bad=1; done
    if ! [[ $mname =~ $PLUGIN_RE ]] || [ "${#plugins[@]}" -eq 0 ] || [ "$bad" = 1 ]; then
      warn "$name: .claude-plugin/marketplace.json has no usable name or plugins; copying its skills to $(tilde "$CLAUDE_SKILLS") instead"
    elif [ -n "${MARKETPLACE_OF[$mname]+x}" ]; then
      warn "$name: marketplace $mname is already provided by ${MARKETPLACE_OF[$mname]}; copying its skills to $(tilde "$CLAUDE_SKILLS") instead"
    else
      MARKETPLACE_OF[$mname]=$name
      CLAUDE_SETTINGS=$(jq -c --arg m "$mname" --arg url "$url" --arg ref "$ref" \
        '.extraKnownMarketplaces[$m] = {source: {source: "git", url: $url, ref: $ref}}' <<<"$CLAUDE_SETTINGS")
      for p in "${plugins[@]}"; do
        CLAUDE_SETTINGS=$(jq -c --arg k "$p@$mname" '.enabledPlugins[$k] = true' <<<"$CLAUDE_SETTINGS")
      done
      to_claude=0
      plugin_note="; Claude Code plugin"
      for p in "${plugins[@]}"; do plugin_note+=" $p@$mname"; done
    fi
  fi

  declare -A matched=()
  n=0
  while IFS= read -r rel; do
    if [ -z "$rel" ]; then
      skill=$name
      path=$dir
    else
      skill=${rel##*/}
      path="$dir/$rel"
    fi
    if [ "${filter[0]}" != "*" ]; then
      want=0
      for f in "${filter[@]}"; do [ "$f" = "$skill" ] && want=1; done
      [ "$want" = 1 ] || continue
      matched[$skill]=1
    fi
    if ! [[ $skill =~ $SKILL_RE ]]; then
      warn "$name: skipping ${rel:-.}: \"$skill\" isn't a kebab-case name"
      continue
    fi
    if [ -n "${WANT_AGENTS[$skill]+x}" ]; then
      warn "$name: skipping $skill: already provided by ${WANT_AGENTS[$skill]%%$'\t'*}"
      continue
    fi
    fm=$(frontmatter_name "$path/SKILL.md")
    if [ "$fm" != "$skill" ]; then
      warn "$name: $skill/SKILL.md declares name \"$fm\"; Coder Agents only loads skills whose name matches the directory"
    fi
    size=$(wc -c <"$path/SKILL.md" | tr -d ' ')
    [ "$size" -le 65536 ] || warn "$name: $skill/SKILL.md is $size bytes; Coder Agents reads only the first 64 KiB"
    WANT_AGENTS[$skill]="$name"$'\t'"$used_ref"$'\t'"$path"
    ORDER_AGENTS+=("$skill")
    # shellcheck disable=SC2034 # read through reconcile's nameref
    if [ "$to_claude" = 1 ]; then
      WANT_CLAUDE[$skill]=${WANT_AGENTS[$skill]}
      ORDER_CLAUDE+=("$skill")
    fi
    n=$((n + 1))
  done < <(list_skill_dirs "$dir")
  if [ "${filter[0]}" != "*" ]; then
    for f in "${filter[@]}"; do
      [ -n "${matched[$f]+x}" ] || warn "$name: no skill named $f"
    done
  fi
  unset matched
  log "$name: $used_ref ($commit), $n skill$([ "$n" = 1 ] || echo s)$plugin_note"
done

NEW_ENTRIES=""
record() { NEW_ENTRIES+="$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"$'\n'; }
owned() { jq -e --arg k "$1" --arg n "$2" '.skills[$k][$n] != null' >/dev/null 2>&1 <<<"$OLD_MANIFEST"; }

# reconcile KEY ROOT WANT ORDER: make ROOT hold exactly the wanted skills that
# this script owns, leaving everything else alone.
reconcile() {
  local key=$1 root=$2
  local -n want=$3 order=$4
  local skill src ref path dest tmp old existed
  local installed=() updated=() removed=() unchanged=0 skipped=0
  for skill in "${order[@]}"; do
    IFS=$'\t' read -r src ref path <<<"${want[$skill]}"
    dest="$root/$skill"
    existed=0
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      existed=1
      if ! owned "$key" "$skill"; then
        warn "$(tilde "$dest") exists and isn't managed here; not installing $skill from $src"
        skipped=$((skipped + 1))
        continue
      fi
      if [ ! -L "$dest" ] && diff -rq "$path" "$dest" >/dev/null 2>&1; then
        record "$key" "$skill" "$src" "$ref"
        unchanged=$((unchanged + 1))
        continue
      fi
    fi
    mkdir -p "$root"
    tmp="$root/.agent-skills-new-$skill"
    old="$root/.agent-skills-old-$skill"
    rm -rf "$tmp" "$old"
    # -L: real files, never links back into the checkout.
    if ! cp -RL "$path" "$tmp" 2>/dev/null; then
      warn "can't copy $skill from $src"
      rm -rf "$tmp"
      [ "$existed" = 1 ] && record "$key" "$skill" "$src" "$ref"
      continue
    fi
    if [ "$existed" = 1 ]; then mv "$dest" "$old"; fi
    if mv "$tmp" "$dest"; then
      rm -rf "$old"
      if [ "$existed" = 1 ]; then updated+=("$skill"); else installed+=("$skill"); fi
    else
      warn "can't install $skill into $(tilde "$root")"
      rm -rf "$tmp"
      [ "$existed" = 1 ] && mv "$old" "$dest"
    fi
    record "$key" "$skill" "$src" "$ref"
  done

  # Owned entries nobody provides any more. A configured source that couldn't
  # be fetched keeps what it installed before.
  while IFS=$'\t' read -r skill src ref; do
    [ -n "$skill" ] || continue
    [ -n "${want[$skill]+x}" ] && continue
    if [ -n "${FAILED[$src]+x}" ]; then
      record "$key" "$skill" "$src" "$ref"
      continue
    fi
    [[ $skill =~ $SKILL_RE ]] || continue
    rm -rf "${root:?}/$skill"
    removed+=("$skill")
  done < <(jq -r --arg k "$key" '.skills[$k] // {} | to_entries[] | [.key, .value.source, .value.ref] | @tsv' <<<"$OLD_MANIFEST")

  if [ $((${#installed[@]} + ${#updated[@]} + ${#removed[@]})) -gt 0 ]; then
    log "$(tilde "$root"): installed ${#installed[@]}${installed[*]:+ (${installed[*]})}, updated ${#updated[@]}${updated[*]:+ (${updated[*]})}, removed ${#removed[@]}${removed[*]:+ (${removed[*]})}, unchanged $unchanged"
    CHANGED=1
  elif [ $((unchanged + skipped)) -gt 0 ]; then
    log "$(tilde "$root"): $unchanged skills, unchanged"
  fi
}

CHANGED=0
reconcile agents "$AGENTS_SKILLS" WANT_AGENTS ORDER_AGENTS
reconcile claude "$CLAUDE_SKILLS" WANT_CLAUDE ORDER_CLAUDE

# Checkouts of sources that are no longer configured.
for d in "$SRC_DIR"/*/; do
  [ -d "$d" ] || continue
  d=${d%/}
  [ -n "${CONFIGURED[${d##*/}]+x}" ] || {
    rm -rf "$d"
    log "removed checkout ${d##*/}"
    CHANGED=1
  }
done

# Manifest: which entries in the skills directories this script owns.
new_manifest=$(printf '%s' "$NEW_ENTRIES" | jq -R -s '
  {version: 1, skills: (split("\n") | map(select(length > 0) | split("\t"))
    | reduce .[] as $e ({agents: {}, claude: {}}; .[$e[0]][$e[1]] = {source: $e[2], ref: $e[3]}))}')
if [ "$(jq -S . <<<"$new_manifest")" != "$(jq -S . <<<"$OLD_MANIFEST" 2>/dev/null)" ]; then
  printf '%s\n' "$new_manifest" >"$MANIFEST.new" && mv "$MANIFEST.new" "$MANIFEST"
fi

# Claude Code managed settings: one drop-in for every registered marketplace.
write_managed() {
  local content=$1 tmp sudo=()
  if [ -z "$content" ] && [ ! -e "$MANAGED_FILE" ]; then return 0; fi
  if [ -n "$content" ] && [ -f "$MANAGED_FILE" ] && [ "$(cat "$MANAGED_FILE")" = "$content" ]; then
    log "Claude Code managed settings unchanged"
    return 0
  fi
  if [ -d "$MANAGED_DIR" ] && [ -w "$MANAGED_DIR" ]; then
    :
  elif [ ! -e "$MANAGED_DIR" ] && mkdir -p "$MANAGED_DIR" 2>/dev/null; then
    :
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo=(sudo -n)
  else
    warn "can't write $MANAGED_DIR without sudo; Claude Code plugins not configured"
    return 0
  fi
  if [ -z "$content" ]; then
    "${sudo[@]}" rm -f "$MANAGED_FILE" && log "removed $MANAGED_FILE"
    CHANGED=1
    return 0
  fi
  tmp=$(mktemp "$DATA_DIR/managed.XXXXXX") || return 0
  printf '%s\n' "$content" >"$tmp"
  if "${sudo[@]}" install -d -m 0755 "$MANAGED_DIR" && "${sudo[@]}" install -m 0644 "$tmp" "$MANAGED_FILE"; then
    log "wrote $MANAGED_FILE ($(jq -r '.extraKnownMarketplaces | keys | join(", ")' <<<"$content"))"
    CHANGED=1
  else
    warn "can't write $MANAGED_FILE"
  fi
  rm -f "$tmp"
}

if [ "$CLAUDE_SETTINGS" = '{}' ]; then
  write_managed ""
else
  write_managed "$(jq -S . <<<"$CLAUDE_SETTINGS")"
fi

[ "$CHANGED" = 1 ] || log "nothing changed"
exit 0
