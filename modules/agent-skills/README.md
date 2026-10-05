# agent-skills

Installs agent skills (directories with a `SKILL.md`) from git
repositories into a Coder workspace, on every start, for every coding agent in it. It's a
shared module: templates use it as `./modules/agent-skills` after
`scripts/vendor-modules.sh` has copied the repository's `modules/` into the template.

```hcl
module "agent_skills" {
  count    = data.coder_workspace.me.start_count
  source   = "./modules/agent-skills"
  agent_id = coder_agent.main.id
  sources = [
    { name = "coder-skills", url = "https://github.com/coder/skills.git", ref = "v0.2.0" },
    { name = "team", url = "git@git.example.com:org/skills.git", ref = "v1.0.0", skills = ["deploy", "triage"] },
  ]
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `agent_id` | string | | The `coder_agent` to run on |
| `sources` | list(object) | `[]` | Repositories, in priority order (see below) |
| `display_name` | string | `Agent skills` | Script name in the startup logs |
| `icon` | string | `/emojis/1f9f0.png` | Script icon; must be a path coderd serves |
| `claude_managed_settings_dir` | string | `/etc/claude-code/managed-settings.d` | Claude Code's managed-settings drop-in directory. Override only for tests |

Each source is:

| Field | Required | Description |
|---|---|---|
| `name` | yes | Short id (`[a-z0-9][a-z0-9._-]*`), used for the checkout and in logs. Unique |
| `url` | yes | Clone URL: `https://…`, `ssh://…` or scp-form `git@host:org/repo.git`. Must not start with `-` |
| `ref` | yes | Tag or branch (a full commit id also works on most forges). Must not start with `-`. Prefer tags: see below |
| `skills` | no | Skill names to install. `"*"` anywhere in the list (the default is `["*"]`) installs all |
| `claude_plugin` | no | Default `true`: register the repo's Claude Code marketplace (see below) |

Output `script` is the rendered startup script, for testing it outside a workspace.

## What the script does

It's one `coder_script` (`run_on_start`, doesn't block login). It needs bash 4.4+, git 2.24+,
jq, `base64`, `cp`, `diff`, `find` and `install`, and, for Claude Code's settings, passwordless
`sudo`. For each source, in order:

1. **Fetch.** A shallow fetch of `ref` into `~/.local/share/agent-skills/src/<name>`. A changed
   `url` gets a fresh clone; a changed `ref` is fetched and checked out. If the fetch fails, it
   logs a warning and keeps using the previous checkout, if there is one. Git never prompts:
   `GIT_TERMINAL_PROMPT=0`, and SSH uses Coder's `GIT_SSH_COMMAND` (the user's Coder SSH key).
   A `url` or `ref` starting with `-` is refused, and the fetch passes `--end-of-options`, so
   neither can be read as a git option.
2. **Find skills.** Every directory with a `SKILL.md`, at any depth, skipping hidden paths and
   skills nested inside another skill. A `SKILL.md` at the repository root makes the repo one
   skill, named after the source. The skill's name is its directory name, filtered by `skills`.
   Names that aren't kebab-case (`^[a-z0-9]+(-[a-z0-9]+)*$`) are skipped with a warning. A
   front-matter `name` that differs from the directory, or a `SKILL.md` over 64 KiB, gets a
   warning: Coder Agents ignores the former and truncates the latter.
3. **Copy** each skill to `~/.agents/skills/<name>`. **Skills must be plain files:** a skill
   that contains a symlink is skipped with a warning (an installed copy is kept), so a link
   can't pull in files from outside the repository. Hidden entries (`.git` and the like) are
   left out of the copy, and ignored when comparing. The copy is built in a temporary
   directory beside the target and swapped in, only when the content changed. When two
   skills have the same name, the first wins (an earlier source, or the first path in sorted
   order within one source), and the warning names both paths.
4. **Claude Code.** Claude Code doesn't read `~/.agents/skills`. If `claude_plugin` is true and
   the repo has `.claude-plugin/marketplace.json`, the marketplace (its `name`, with
   `{"source": "git", "url": <url>, "ref": <ref>}`) goes into `extraKnownMarketplaces`, and each
   of its `plugins[].name` into `enabledPlugins` as `<plugin>@<marketplace>`. Claude Code clones
   the marketplace itself, in the background, at the start of a session. Otherwise, the skills
   are also copied to `~/.claude/skills/<name>`.

All the marketplaces go into one file, `<claude_managed_settings_dir>/30-agent-skills.json`,
installed mode 0644 (with `sudo` when the directory isn't writable), and rewritten only when
it changes. It's removed when no source has a marketplace. Without sudo, the script warns and
skips it.

### Ownership

`~/.local/share/agent-skills/manifest.json` records which entries in `~/.agents/skills` and
`~/.claude/skills` the script installed, and from which source and ref. Only those entries are
updated or removed. The manifest is rewritten atomically after every change, and an entry is
recorded before its folder is swapped in, so an interrupted run leaves nothing orphaned: the
next run finishes or undoes a half-done swap (`.agent-skills-new-*`, `.agent-skills-old-*`).

- An owned entry that no source provides any more is removed. Entries from a configured source
  that can't be fetched (and has no previous checkout) are kept.
- An entry the script doesn't own is never touched. If one has the same name as an incoming
  skill, the incoming skill is skipped with a warning that says how to resolve it. The
  exception is a folder identical to the incoming skill, which is adopted: nothing in it can
  be lost, and it's how ownership is recovered after a lost manifest.
- An unreadable manifest is moved aside to `manifest.json.corrupt-<timestamp>`, with a warning,
  and a new one is started.
- Edits to an owned entry are overwritten on the next start.

Checkouts of sources that are no longer configured are deleted. An empty `sources` list removes
everything the script installed.

### Notes

- `skills` filters the copies. A Claude Code plugin always brings all of its skills; set
  `claude_plugin = false` to apply the filter to Claude Code too.
- Plugins in managed settings can't be turned off inside the workspace.
- **Trust.** A marketplace plugin can ship hooks and MCP servers, which run in every workspace.
  With a branch as `ref`, whoever can push to that branch can change them at any time, and
  the next start installs the change. Prefer tags, from repositories you trust.
- The first Claude Code session after the marketplace is added may need `/reload-plugins`.
- One failing source never stops the others. The script exits 0 unless it can't run at all
  (no bash 4.4, git or jq, or bad input).

## Where agents look

| Agent | Reads |
|---|---|
| Claude Code | `~/.claude/skills`, plus plugins from managed settings |
| Codex | `~/.agents/skills` (recursive) |
| opencode | `~/.agents/skills` and `~/.claude/skills` |
| Xum (formerly Mux) | `~/.agents/skills` (one level) |
| Coder Agents | `CODER_AGENT_EXP_SKILLS_DIRS` (one level, no symlinked skill directories). Setting it replaces the default `~/.coder/skills,.agents/skills`, so a template that sets it should list `~/.agents/skills` and keep the defaults |
