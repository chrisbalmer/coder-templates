#!/usr/bin/env bash
# Installs a pinned herdr into ~/.local/bin, installs herdr's agent
# integrations, writes its agent skill and, optionally, starts its headless
# server. Runs on every start and is idempotent. See ../README.md for the behaviour in full. Stays bash 3.2
# compatible, for macOS workspaces.
#
# Input (environment; Terraform validates every value):
#   HERDR_VERSION           release, e.g. 0.9.3
#   HERDR_CHECKSUMS         space-separated <platform>=<sha256>
#   HERDR_INSTALL           true to install into ~/.local/bin, false to use PATH
#   HERDR_INTEGRATIONS      space-separated integration names
#   HERDR_SKILL             true to write the agent skill
#   HERDR_SYNC_UNIT         this script's coder exp sync unit
#   HERDR_WAIT_FOR          space-separated sync units to wait for before the
#                           integrations (the agents' install scripts)
#   HERDR_START_SERVER      true to start herdr's headless server
#   HERDR_WORKDIR           directory the server starts in (empty: home)
#   HERDR_INTEGRATION_WAIT  seconds to wait for an agent's config directory
#                           (default 120; the agent may still be installing)
#
# Problems with ordering, integrations, the skill or the server are logged as
# WARN and the script still exits 0. It exits 1 only when there is no usable herdr.
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
UNIT=${HERDR_SYNC_UNIT:-}
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/herdr-module"
# Agents (claude) and herdr itself install here; the server's panes inherit it.
export PATH="$BIN_DIR:$PATH"

# Other scripts may wait for this one; tell them when it's done, however it
# ends. Without the coder CLI (outside a workspace) there's nothing to order.
HAVE_SYNC=false
if [ -n "$UNIT" ] && command -v coder >/dev/null 2>&1; then
  HAVE_SYNC=true
  trap 'coder exp sync complete "$UNIT" >/dev/null 2>&1' EXIT
fi

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
  local content dir dirs claude_dir
  content=$("$HERDR" --skill 2>/dev/null) || content=
  if [ -z "$content" ]; then
    warn "herdr --skill printed nothing; skill not written"
    return 0
  fi
  dirs=("$HOME/.agents/skills/herdr")
  claude_dir=$(agent_dir claude)
  [ -d "$claude_dir" ] && dirs+=("$claude_dir/skills/herdr")
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

# Waits for HERDR_WAIT_FOR (the agents' install scripts), then marks this
# unit started. The download doesn't need the agents, so it happens first.
wait_for_agents() {
  [ "$HAVE_SYNC" = true ] || return 0
  if [ -n "${HERDR_WAIT_FOR:-}" ]; then
    # shellcheck disable=SC2086 # one argument per unit
    coder exp sync want "$UNIT" $HERDR_WAIT_FOR >/dev/null 2>&1 ||
      warn "couldn't declare the wait for: $HERDR_WAIT_FOR"
  fi
  if coder exp sync start "$UNIT" --timeout 10m >/dev/null 2>&1; then
    [ -z "${HERDR_WAIT_FOR:-}" ] || log "waited for: $HERDR_WAIT_FOR"
  else
    warn "gave up waiting for: ${HERDR_WAIT_FOR:-nothing}; continuing"
  fi
}

# The config directory herdr's integration needs, for agents whose CLI has
# the integration's name.
agent_dir() {
  case $1 in
  claude) printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ;;
  codex) printf '%s' "${CODEX_HOME:-$HOME/.codex}" ;;
  *) return 1 ;;
  esac
}

# herdr integration install is idempotent, and refuses until the agent's
# config directory exists. An installed agent may not have created it yet
# (Claude Code's installer doesn't), so create it when the agent's CLI is
# there. Without the CLI, the agent may still be installing (no ordering), so
# retry for up to WAIT seconds.
install_integration() {
  local name=$1 out dir deadline=$((SECONDS + WAIT))
  if dir=$(agent_dir "$name") && [ ! -d "$dir" ] && command -v "$name" >/dev/null 2>&1; then
    mkdir -p "$dir" && log "created $(tilde "$dir") for $name"
  fi
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

# Not a pipe into grep -q: with pipefail, grep exiting early can fail the
# pipeline even on a match.
server_running() {
  local out
  out=$("$HERDR" status server 2>/dev/null) || return 1
  case $out in
  *"status: running"*) return 0 ;;
  *) return 1 ;;
  esac
}

# herdr server runs in the foreground, so detach it: no stdin, output to a
# log, its own session where setsid exists (Linux). It restores the saved
# layout and resumes agents with an integration. herdr saves the layout on
# every change and on SIGTERM, so a workspace stop loses nothing.
start_server() {
  local dir=${HERDR_WORKDIR:-$HOME} log _
  if server_running; then
    log "server is already running"
    return 0
  fi
  [ -d "$dir" ] || dir=$HOME
  mkdir -p "$STATE_DIR" || {
    warn "can't create $STATE_DIR; server not started"
    return 0
  }
  log="$STATE_DIR/server.log"
  if command -v setsid >/dev/null 2>&1; then
    (cd "$dir" && exec setsid "$HERDR" server </dev/null >>"$log" 2>&1 &)
  else
    (cd "$dir" && exec nohup "$HERDR" server </dev/null >>"$log" 2>&1 &)
  fi
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if server_running; then
      log "server started in $(tilde "$dir")"
      return 0
    fi
    sleep 0.5
  done
  warn "server didn't start within 10s; see $(tilde "$log")"
}

# Integrations after the agents are installed, and before the skill: it goes
# to ~/.claude only once that exists. The server last, so restored agents
# find their CLI and resume through their integration.
wait_for_agents
for name in ${HERDR_INTEGRATIONS:-}; do
  install_integration "$name"
done
if [ "${HERDR_SKILL:-true}" = true ]; then
  write_skill
fi
if [ "${HERDR_START_SERVER:-false}" = true ]; then
  start_server
fi
exit 0
