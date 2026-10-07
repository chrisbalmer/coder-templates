# herdr

Installs [herdr](https://herdr.dev), a terminal multiplexer for coding agents, into a Coder
workspace, and adds a **Herdr** app that opens it. The install is a pinned release with a
verified checksum. On every start the module also installs herdr's agent integrations and writes
its agent skill, so after a workspace restart herdr can restore its layout and resume agent
conversations. It's a shared module: templates here use it as `./modules/herdr` after
`scripts/vendor-modules.sh` has copied the repository's `modules/` into the template.

```hcl
module "herdr" {
  count    = data.coder_workspace.me.start_count
  source   = "./modules/herdr"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/project"
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
| `app` | bool | `true` | Add the Herdr app |
| `workdir` | string | `null` | Absolute path the app starts herdr in, when it exists. `null` is the home directory |
| `display_name` | string | `Herdr` | App name, and the script's name in the startup logs |
| `icon` | string | `/emojis/1f411.png` | Must be a path coderd serves. coderd doesn't ship a herdr icon |
| `slug`, `order`, `group` | | `herdr`, `null`, `null` | App placement |

## What the script does

One `coder_script` (`run_on_start`, doesn't block login). It needs bash (3.2 or later, so macOS
works), `curl`, `mktemp`, and `sha256sum` or `shasum`. On every start:

1. **Install.** If `~/.local/bin/herdr` already has the pinned checksum, nothing is downloaded.
   Otherwise it downloads `herdr-<os>-<arch>` for `herdr_version` from the GitHub release, checks
   the SHA-256, and moves it into `~/.local/bin/herdr` atomically. A wrong checksum leaves nothing
   behind. The checksum decides, not `herdr --version`, so a `herdr update` run in the workspace
   is put back to the pin on the next start. With `install = false` it uses `herdr` from `PATH`.
2. **Integrations.** Runs `herdr integration install <name>` for each entry. It's idempotent, and
   for Claude Code it adds a hook script to `~/.claude/hooks` and a `SessionStart` hook to
   `~/.claude/settings.json`, keeping everything else in that file. herdr refuses until the
   agent's config directory exists. On a first start the agent may still be installing, so the
   script retries for up to two minutes, then logs a warning and tries again on the next start.
3. **Skill.** Writes `herdr --skill` (it matches the installed version) to
   `~/.agents/skills/herdr/SKILL.md`, and to `~/.claude/skills/herdr/SKILL.md` when `~/.claude`
   exists. Unchanged files aren't rewritten. The skill tells an agent to use herdr only when asked
   to, and only inside a herdr pane.

Problems with integrations or the skill are warnings. The script fails only when there is no
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
- The server's lifetime. Opening the app or running `herdr` starts the server, which then restores
  the saved layout. Nothing starts it at workspace start.

## Updating the pin

```bash
./scripts/herdr-checksums.sh 0.9.4   # prints the table entry from the release's asset digests
```

Add the entry to `builtin_checksums` in `main.tf`, change the `herdr_version` default, and run
`./scripts/test-herdr-module.sh` and `terraform test` (from `modules/herdr`).
