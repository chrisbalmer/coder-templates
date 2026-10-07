# herdr

Installs [herdr](https://herdr.dev), a terminal multiplexer for coding agents, into a Coder
workspace, and adds a **Herdr** app that opens it. The install is a pinned release with a
verified checksum. On every start the module also installs herdr's agent integrations and writes
its agent skill, so after a workspace restart herdr can restore its layout and resume agent
conversations. It can wait for the agents' own modules to finish installing, and it can start
herdr's server at workspace start. It's a shared module: templates here use it as `./modules/herdr` after
`scripts/vendor-modules.sh` has copied the repository's `modules/` into the template.

```hcl
module "herdr" {
  count            = data.coder_workspace.me.start_count
  source           = "./modules/herdr"
  agent_id         = coder_agent.main.id
  workdir          = "/home/coder/project"
  wait_for_scripts = flatten(module.claude-code[*].scripts) # registry claude-code module
  start_server     = true
}
```

From another repository, use a module tag:

```hcl
source = "git::https://github.com/chrisbalmer/coder-templates.git//modules/herdr?ref=modules/herdr/v1.0.0"
```

## Why a workspace restart matters

Stopping a workspace ends every process in it, so it's the same as a herdr server restart. What
herdr needs to come back is in the home directory, which a workspace normally keeps:

| Event | Agent processes | Layout | Agent conversation |
|---|---|---|---|
| Browser tab or SSH connection drops | Keep running | Kept | Kept |
| Workspace stop and start | Gone | Restored from `~/.config/herdr` | Resumed, for agents with an integration |
| Workspace delete | Gone | Gone | Gone |

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `agent_id` | string | | The `coder_agent` to run on |
| `herdr_version` | string | `0.9.3` | Release to install, without the `v` |
| `checksums` | map(string) | `{}` | SHA-256 per platform (`linux-x86_64`, `linux-aarch64`, `macos-x86_64`, `macos-aarch64`). Empty uses the module's table, which covers the default version |
| `install` | bool | `true` | `false` uses the `herdr` already on `PATH`, for an image that bakes it in |
| `integrations` | list(string) | `["claude"]` | Agent integrations to install (`herdr integration install <name>`). `herdr integration status` lists the names |
| `install_skill` | bool | `true` | Write herdr's agent skill to `~/.agents/skills/herdr` and `~/.claude/skills/herdr` |
| `wait_for_scripts` | list(string) | `[]` | `coder exp sync` units to wait for before the integrations and the server, such as the registry claude-code module's `scripts` output |
| `start_server` | bool | `false` | Start herdr's headless server on every start (see [The server](#the-server)) |
| `app` | bool | `true` | Add the Herdr app |
| `workdir` | string | `null` | Absolute path the app, and a started server, start herdr in, when it exists. `null` is the home directory |
| `display_name` | string | `Herdr` | App name, and the script's name in the startup logs |
| `icon` | string | `/emojis/1f411.png` | Must be a path coderd serves. coderd doesn't ship a herdr icon |
| `slug`, `order`, `group` | | `herdr`, `null`, `null` | App placement. The slug also names the script's sync unit, `<slug>-script` |

## Outputs

| Name | Description |
|---|---|
| `scripts` | The script's `coder exp sync` unit (`["herdr-script"]`), for scripts that should wait for herdr |
| `script`, `app_command` | The rendered script and app command, for tests |

## What the script does

One `coder_script` (`run_on_start`, doesn't block login). It needs bash (3.2 or later, so macOS
works), `curl`, `mktemp`, and `sha256sum` or `shasum`. On every start:

1. **Install.** If `~/.local/bin/herdr` already has the pinned checksum, nothing is downloaded.
   Otherwise it downloads `herdr-<os>-<arch>` for `herdr_version` from the GitHub release, checks
   the SHA-256, and moves it into `~/.local/bin/herdr` atomically. A wrong checksum leaves nothing
   behind. The checksum decides, not `herdr --version`, so a `herdr update` run in the workspace
   is put back to the pin on the next start. With `install = false` it uses `herdr` from `PATH`.
2. **Wait.** With `wait_for_scripts`, it waits (up to 10 minutes) for those units to complete,
   through `coder exp sync`, which Coder's agent provides. Script units mark themselves complete
   however they end, so a failed agent install doesn't hold herdr up. The download happens before
   the wait, since it doesn't need the agents. The script always registers its own unit, and
   marks it complete when it exits, so other scripts can wait for herdr.
3. **Integrations.** Runs `herdr integration install <name>` for each entry. It's idempotent, and
   for Claude Code it adds a hook script to `~/.claude/hooks` and a `SessionStart` hook to
   `~/.claude/settings.json`, keeping everything else in that file. herdr refuses until the
   agent's config directory exists, which Claude Code's installer doesn't create, so when the
   agent's CLI (`claude`, `codex`) is on `PATH` the script creates the directory
   (`CLAUDE_CONFIG_DIR` and `CODEX_HOME` are honoured). Without the CLI, say with no
   `wait_for_scripts` and the agent still installing, it retries for up to two minutes, then
   logs a warning and tries again on the next start.
4. **Skill.** Writes `herdr --skill` (it matches the installed version) to
   `~/.agents/skills/herdr/SKILL.md`, and to `~/.claude/skills/herdr/SKILL.md` when `~/.claude`
   exists. Unchanged files aren't rewritten. The skill tells an agent to use herdr only when asked
   to, and only inside a herdr pane.
5. **Server** (with `start_server`). See below.

Problems with ordering, integrations, the skill or the server are warnings. The script fails only when there is no
usable herdr: a failed download with no earlier install, or `install = false` and no `herdr` on
`PATH`. A failed download with an earlier install keeps using it.

The app runs `herdr` from `~/.local/bin` with that directory first on `PATH`, so herdr's panes, and
the agents in them, find the `herdr` CLI even when no shell profile adds it. Add `~/.local/bin` to
`PATH` in your shell profile to run `herdr` from other terminals.

## What it leaves alone

- `~/.config/herdr/config.toml`. It's yours: put it in your dotfiles. Since the module owns the
  version, you'll probably want herdr's update notice off:

  ```toml
  [update]
  version_check = false
  ```

- herdr plugins. They're third-party code; install them yourself.

## The server

herdr keeps its panes in a server process. Without `start_server`, opening the app or running
`herdr` starts it, and it then restores the saved layout. With `start_server = true`, the script
starts it at the end of every workspace start (`herdr server`, detached, from `workdir`), unless
one is already running. The layout is restored, and agents with an integration are resumed into
their conversations, before anyone opens herdr. That's after the wait, so restored agents find
their CLI. Its output goes to `~/.local/state/herdr-module/server.log`; herdr's own log is
`~/.config/herdr/herdr-server.log`.

herdr saves the layout whenever it changes and when it gets SIGTERM, so a workspace stop doesn't
lose it. A started server keeps every restored agent running, which costs memory, but not tokens
until you prompt it.

## Updating the pin

```bash
./scripts/herdr-checksums.sh 0.9.4   # prints the table entry from the release's asset digests
```

Add the entry to `builtin_checksums` in `main.tf`, change the `herdr_version` default, and run
`./scripts/test-herdr-module.sh` and `terraform test` (from `modules/herdr`).
