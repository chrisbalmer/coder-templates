#!/usr/bin/env bash
# Installs a pinned herdr into ~/.local/bin, installs herdr's agent
# integrations and writes its agent skill. Runs on every start and is
# idempotent. See ../README.md for the behaviour in full. Stays bash 3.2
# compatible, for macOS workspaces.
#
# Input (environment; Terraform validates every value):
#   HERDR_VERSION           release, e.g. 0.9.3
#   HERDR_CHECKSUMS         space-separated <platform>=<sha256>
#   HERDR_INSTALL           true to install into ~/.local/bin, false to use PATH
#   HERDR_INTEGRATIONS      space-separated integration names
#   HERDR_SKILL             true to write the agent skill
#   HERDR_INTEGRATION_WAIT  seconds to wait for an agent's config directory
#                           (default 120; the agent may still be installing)
#
# Problems with integrations or the skill are logged as WARN and the script
# still exits 0. It exits 1 only when there is no usable herdr.
set -uo pipefail

log() { printf '[herdr] %s\n' "$*"; }
warn() { printf '[herdr] WARN: %s\n' "$*"; }
first_line() { printf '%s\n' "$1" | sed -n '/[^[:space:]]/{p;q;}'; }
tilde() {
  case $1 in
  "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
  *) printf '%s' "$1" ;;
  esac
}

VERSION=${HERDR_VERSION:-}
INSTALL=${HERDR_INSTALL:-true}
WAIT=${HERDR_INTEGRATION_WAIT:-120}
BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/herdr"

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

platform() {
  local os arch
  case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=macos ;;
  *) return 1 ;;
  esac
  case "$(uname -m)" in
  x86_64 | amd64) arch=x86_64 ;;
  aarch64 | arm64) arch=aarch64 ;;
  *) return 1 ;;
  esac
  printf '%s-%s' "$os" "$arch"
}

checksum_for() {
  local entry
  for entry in ${HERDR_CHECKSUMS:-}; do
    if [ "${entry%%=*}" = "$1" ]; then
      printf '%s' "${entry#*=}"
      return 0
    fi
  done
  return 1
}

# Puts the pinned release at ~/.local/bin/herdr, unless it's already there.
# The binary's checksum, not its --version, decides, so a herdr update run in
# the workspace is put back to the pin.
install_herdr() {
  local plat want url tmp got
  plat=$(platform) || {
    warn "unsupported platform: $(uname -sm)"
    return 1
  }
  want=$(checksum_for "$plat") || {
    warn "no checksum for herdr $VERSION on $plat"
    return 1
  }
  if [ -x "$BIN" ] && [ "$(sha256 "$BIN")" = "$want" ]; then
    log "herdr $VERSION is installed"
    return 0
  fi
  for cmd in curl mktemp; do
    command -v "$cmd" >/dev/null 2>&1 || {
      warn "$cmd not found"
      return 1
    }
  done
  mkdir -p "$BIN_DIR" || {
    warn "can't create $BIN_DIR"
    return 1
  }
  # In the target directory, so the final mv is atomic.
  tmp=$(mktemp "$BIN_DIR/.herdr.XXXXXX") || {
    warn "can't write to $BIN_DIR"
    return 1
  }
  url="https://github.com/herdrdev/herdr/releases/download/v$VERSION/herdr-$plat"
  log "downloading herdr $VERSION for $plat"
  if ! curl -fsSL --retry 3 --connect-timeout 10 --max-time 300 -o "$tmp" "$url"; then
    rm -f "$tmp"
    warn "download failed: $url"
    return 1
  fi
  got=$(sha256 "$tmp")
  if [ "$got" != "$want" ]; then
    rm -f "$tmp"
    warn "checksum mismatch for $url: got $got, want $want"
    return 1
  fi
  if ! { chmod 0755 "$tmp" && mv -f "$tmp" "$BIN"; }; then
    rm -f "$tmp"
    warn "can't install $BIN"
    return 1
  fi
  log "installed herdr $VERSION to ~/.local/bin/herdr"
}

# Writes herdr's own skill, so it always matches the installed version: to
# ~/.agents/skills, and to ~/.claude/skills when Claude Code's directory
# exists (creating it would make herdr and others think Claude Code is
# installed). Only the herdr folder is touched; agent-content never removes
# folders it didn't install.
write_skill() {
  local content dir dirs
  content=$("$HERDR" --skill 2>/dev/null) || content=
  if [ -z "$content" ]; then
    warn "herdr --skill printed nothing; skill not written"
    return 0
  fi
  dirs=("$HOME/.agents/skills/herdr")
  [ -d "$HOME/.claude" ] && dirs+=("$HOME/.claude/skills/herdr")
  for dir in "${dirs[@]}"; do
    if [ -f "$dir/SKILL.md" ] && [ "$(cat "$dir/SKILL.md")" = "$content" ]; then
      continue
    fi
    if mkdir -p "$dir" && printf '%s\n' "$content" >"$dir/SKILL.md.tmp" && mv -f "$dir/SKILL.md.tmp" "$dir/SKILL.md"; then
      log "wrote skill to $(tilde "$dir")"
    else
      rm -f "$dir/SKILL.md.tmp"
      warn "can't write skill to $dir"
    fi
  done
}

# herdr integration install is idempotent, and refuses until the agent's
# config directory exists. On a first start the agent may still be
# installing, so retry for up to WAIT seconds.
install_integration() {
  local name=$1 out deadline=$((SECONDS + WAIT))
  until out=$("$HERDR" integration install "$name" </dev/null 2>&1); do
    if [ "$SECONDS" -ge "$deadline" ]; then
      warn "integration $name not installed: $(first_line "$out")"
      return 0
    fi
    sleep 5
  done
  log "integration $name is installed"
}

if [ "$INSTALL" = true ]; then
  install_herdr
  if [ ! -x "$BIN" ]; then
    warn "herdr is not installed"
    exit 1
  fi
  HERDR=$BIN
else
  HERDR=$(command -v herdr) || {
    warn "install is false and herdr is not on PATH"
    exit 1
  }
  log "using $HERDR ($("$HERDR" --version 2>/dev/null))"
fi

# Integrations first: they wait for agents that are still installing, and the
# skill goes to ~/.claude only once it exists.
for name in ${HERDR_INTEGRATIONS:-}; do
  install_integration "$name"
done
if [ "${HERDR_SKILL:-true}" = true ]; then
  write_skill
fi
exit 0
