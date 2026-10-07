#!/usr/bin/env bash
# Runs modules/herdr/scripts/run.sh against throwaway home directories, the
# way a workspace start does, and checks what it leaves behind. Downloads the
# real herdr release (about 30 MB) once. Linux or macOS.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
run_sh="$root/modules/herdr/scripts/run.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

case "$(uname -s)-$(uname -m)" in
Linux-x86_64) plat=linux-x86_64 ;;
Linux-aarch64) plat=linux-aarch64 ;;
Darwin-x86_64) plat=macos-x86_64 ;;
Darwin-arm64) plat=macos-aarch64 ;;
*) echo "unsupported platform" >&2 && exit 1 ;;
esac
version=$(sed -n 's/^    "\([0-9.]*\)" = {$/\1/p' "$root/modules/herdr/main.tf" | head -1)
sum=$(sed -n "s/^ *\"$plat\" *= \"\([0-9a-f]*\)\"$/\1/p" "$root/modules/herdr/main.tf" | head -1)
[ -n "$version" ] && [ -n "$sum" ] || { echo "can't read the checksum table" >&2 && exit 1; }

sha() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

fail=0
check() { # check <description> <command...>
  local d=$1
  shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d" && fail=1; fi
}
# run <home> <log> [VAR=value...]: run.sh with defaults, returns its status.
run() {
  local home=$1 log=$2
  shift 2
  env -i PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="$home" \
    HERDR_VERSION="$version" HERDR_CHECKSUMS="$plat=$sum" HERDR_INSTALL=true \
    HERDR_INTEGRATIONS=claude HERDR_SKILL=true HERDR_INTEGRATION_WAIT=0 \
    "$@" bash "$run_sh" >"$log" 2>&1
}

# 1. First start: downloads, verifies, installs; skill and integration land.
h1="$work/h1"
mkdir -p "$h1/.claude"
echo '{"model":"opus"}' >"$h1/.claude/settings.json"
check "first run exits 0" run "$h1" "$work/1.log"
check "first run downloads" grep -q "downloading herdr $version" "$work/1.log"
check "binary has the pinned checksum" test "$(sha "$h1/.local/bin/herdr")" = "$sum"
check "no temp files left" test -z "$(find "$h1/.local/bin" -name '.herdr.*')"
check "log shows ~ paths" grep -q "wrote skill to ~/.agents/skills/herdr" "$work/1.log"
check "skill in ~/.agents/skills" grep -q '^name: herdr' "$h1/.agents/skills/herdr/SKILL.md"
check "skill in ~/.claude/skills" grep -q '^name: herdr' "$h1/.claude/skills/herdr/SKILL.md"
check "claude hook installed" test -x "$h1/.claude/hooks/herdr-agent-state.sh"
check "claude settings keep existing keys" grep -q '"model"' "$h1/.claude/settings.json"
check "claude settings gain the hook" grep -q 'herdr-agent-state.sh' "$h1/.claude/settings.json"

# 2. Second start: nothing to download or rewrite.
cp "$h1/.claude/settings.json" "$work/settings.before"
check "second run exits 0" run "$h1" "$work/2.log"
check "second run skips the download" grep -q "herdr $version is installed" "$work/2.log"
check "second run doesn't download" bash -c "! grep -q downloading '$work/2.log'"
check "second run leaves the skill alone" bash -c "! grep -q 'wrote skill' '$work/2.log'"
check "second run leaves settings alone" cmp -s "$work/settings.before" "$h1/.claude/settings.json"

# 3. A replaced binary (say, herdr update) goes back to the pin.
printf 'not herdr\n' >"$h1/.local/bin/herdr"
check "replaced binary: exits 0" run "$h1" "$work/3.log"
check "replaced binary: downloads again" grep -q "downloading herdr $version" "$work/3.log"
check "replaced binary: restored" "$h1/.local/bin/herdr" --version

# 4. A wrong checksum installs nothing.
h4="$work/h4"
mkdir -p "$h4"
if run "$h4" "$work/4.log" HERDR_CHECKSUMS="$plat=$(printf '%064d' 0)"; then
  echo "FAIL bad checksum exits 1" && fail=1
else
  echo "ok   bad checksum exits 1"
fi
check "bad checksum: reports the mismatch" grep -q "checksum mismatch" "$work/4.log"
check "bad checksum: no binary" test ! -e "$h4/.local/bin/herdr"
check "bad checksum: no temp files" test -z "$(find "$h4" -name '.herdr.*')"

# 5. No ~/.claude yet: the integration is skipped with a warning, not an error.
h5="$work/h5"
mkdir -p "$h5/.local/bin"
cp "$h1/.local/bin/herdr" "$h5/.local/bin/herdr"
check "missing ~/.claude exits 0" run "$h5" "$work/5.log"
check "missing ~/.claude warns" grep -q "WARN: integration claude not installed" "$work/5.log"
check "missing ~/.claude: not created" test ! -e "$h5/.claude"
check "missing ~/.claude: skill still in ~/.agents" test -f "$h5/.agents/skills/herdr/SKILL.md"

# 6. install=false uses herdr from PATH, or fails without one.
h6="$work/h6"
mkdir -p "$h6"
check "install=false with herdr on PATH exits 0" run "$h6" "$work/6.log" HERDR_INSTALL=false PATH="$h1/.local/bin:/usr/bin:/bin"
check "install=false doesn't install" test ! -e "$h6/.local/bin/herdr"
if run "$h6" "$work/7.log" HERDR_INSTALL=false; then
  echo "FAIL install=false without herdr exits 1" && fail=1
else
  echo "ok   install=false without herdr exits 1"
fi

if [ "$fail" != 0 ]; then
  for f in "$work"/*.log; do echo "--- $(basename "$f")" && cat "$f"; done
fi
exit "$fail"
