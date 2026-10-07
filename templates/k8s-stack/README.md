# Linux Stack on Kubernetes

A headless Linux container workspace on Kubernetes, for
development work in a terminal or VS Code. Pick a **preset**: it chooses the
toolchain image and any throwaway lab databases. Use `General` if you're unsure.
It has no graphical desktop.

| Preset | Image | Size | Labs |
|---|---|---|---|
| General (default) | `base` | 2 CPU / 4 GiB | none |
| Cortex content | `cortex` | 2 CPU / 4 GiB | none |
| Infrastructure | `infra` | 2 CPU / 4 GiB | none |
| Go service | `golang` | 4 CPU / 8 GiB | Postgres |
| App (Go + React) | `app` | 4 CPU / 8 GiB | Postgres, MinIO |

Every image has git, Python and uv, kubectl, sudo, the lab clients (`psql`,
`mysql`, and the MinIO client `mc`), and the GitHub, Gitea and Forgejo CLIs
(`gh`, `tea`, `fj`), the Gitea/Forgejo MCP server `gitea-mcp` (installed, not configured), plus `nc`
for network checks. The image can't be changed after the workspace
is created. CPU, memory, disk size, the repo and the lab toggles can.

## Lab services

The `lab_postgres`, `lab_minio` and `lab_mysql` toggles each create a
throwaway service in the workspace's own namespace when it starts. The service
is **deleted when the workspace stops**, so a restart gives you an empty
database. Turn a toggle on in the workspace settings and restart to add one.

Connection details are written to `~/.config/lab/env` on every start, and login
shells load them:

| Lab | Variables |
|---|---|
| Postgres | `DATABASE_URL`, `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE` |
| MinIO (S3) | `MINIO_ENDPOINT`, `AWS_ENDPOINT_URL_S3`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`; bucket `test`, `mc` alias `lab` |
| MySQL | `MYSQL_URL`, `MYSQL_HOST`, `MYSQL_TCP_PORT`, `MYSQL_USER`, `MYSQL_PWD`, `MYSQL_DATABASE` |

The startup log shows how long each lab took to become ready (usually under a
minute).

## What survives

- **Stop:** your home directory (`/home/coder`) and the workspace's namespace
  are kept. The container and the lab services are removed. MinIO is the one
  exception: its data volume is kept and reused on the next start.
- **Delete:** everything goes, including the home directory.
- **Backups:** the template does not back anything up. Your home directory is
  protected only if your administrator backs up the `home` volume; lab data is
  scratch and is not meant to be kept. Push work you care about.

Install tools with `sudo apt-get install`, or into your home directory. Changes
outside `/home/coder` are lost when the workspace stops.

## Autostop

A workspace stops **8 hours after it starts**. While you're using it, each bit of activity
pushes the stop time back to at least an hour away: a terminal, SSH or VS Code session, a
port forward, or an app opened through Coder.

Background work with nothing connected, such as a detached coding agent or a build left
running after you disconnect, **doesn't count as activity**, so the workspace can stop
underneath it. Your home directory is kept when it stops (see **What survives**).

To change the schedule, open the workspace's **Settings → Schedule**, or use the CLI:

- `coder schedule stop <workspace> 12h` sets how long it runs after each start
  (`manual` turns autostop off). It takes effect from the next start.
- `coder schedule extend <workspace> 2h` moves the current stop time to 2 hours from now.
- `coder schedule show <workspace>` shows the schedule.

A workspace created before the template had this schedule keeps the one it had, which may
be none: check it with `coder schedule show`.

## Dotfiles

The **Dotfiles URL** setting is applied with `coder dotfiles` on every start, so changes to your
dotfiles repository reach the workspace at its next start. It's pre-filled with your admin's
default (out of the box, `git@github.com:<your Coder username>/dotfiles.git`). Change it, or
clear it to skip dotfiles. An SSH URL uses your Coder SSH key (`coder publickey`), which must be
added to your account on that forge; a public repository can use an `https://` URL instead.

## Git identity

Set your name and email in your own git config, ideally in your dotfiles, so it's the same on every
machine. `~/.config/git/config` or `~/.gitconfig` both work, and a repo's own `git config user.email`
overrides both. If you set nothing, commits use your Coder name and login email: the template
writes those to `/etc/gitconfig` as a fallback on every start. The "Git identity fallback"
startup log shows which identity is in effect.

## Agent skills

Every start installs **agent skills** (folders with a `SKILL.md` that teach a coding agent a
workflow) from git repositories your admin chooses. Out of the box that's
[chrisbalmer/ai-tools](https://github.com/chrisbalmer/ai-tools) and
[coder/skills](https://github.com/coder/skills), at pinned tags. The "Agent content" startup log
lists what was installed, and any repository it couldn't reach.

| Agent | Where it finds them |
|---|---|
| Codex, opencode, Xum, Coder Agents | `~/.agents/skills/<name>` (copies) |
| Claude Code | As plugins (for example `ai-tools@ai-tools`), set in Claude Code's managed settings. Repositories that aren't Claude Code plugins are copied to `~/.claude/skills/<name>` instead |

- Claude Code fetches the plugins in the background when a session starts, so the **first
  session may not show them: run `/reload-plugins`**, or start a new session.
- Plugins installed this way are set by the template (managed settings), so they **can't be
  turned off** inside the workspace.
- Your own skills are safe: the template only updates or removes skills it installed itself, and
  never replaces a folder you created, unless it has the name of a skill the template installed
  earlier. If you have a skill with the same name as one it installs, yours stays and the
  startup log says so (remove your folder to get the template's). Edits to a skill the template
  installed are overwritten on the next start; copy it under a new name to change it.
- Coder Agents also reads `~/.coder/skills` and your repository's `.agents/skills`.

**For admins:** the template variable `agent_content_sources` is a JSON list, passed on every push
like the other template variables (see `REQUIREMENTS.md`). Each entry has a `name`, a clone
`url` and a `ref` (a tag or branch), plus two optional fields:

- `skills`: the names to copy. All by default, or when the list contains `"*"`. A Claude Code
  plugin always brings all of its skills.
- `claude_plugin`: default `true`. `false` copies the skills to `~/.claude/skills` instead of
  registering the repository as a Claude Code plugin marketplace.

Earlier entries win when two provide the same skill name, and `[]` removes everything the
template installed. Skills must be plain files: one that contains a symlink is skipped.

A Claude Code plugin can ship hooks and MCP servers, which then run in every workspace. With a
branch as `ref`, whoever can push to that branch can change them at any time, so prefer tags,
from repositories you trust.

For example, to add a private repository:

```json
[
  {"name": "ai-tools", "url": "https://github.com/chrisbalmer/ai-tools.git", "ref": "v0.4.0"},
  {"name": "coder-skills", "url": "https://github.com/coder/skills.git", "ref": "v0.2.0"},
  {"name": "team", "url": "git@git.example.com:org/skills.git", "ref": "v1.0.0", "skills": ["deploy", "review-checklist"]}
]
```

In this repository's `CODER_TEMPLATE_VARIABLES` it can also be written as a YAML list, which CI
passes on as JSON. An SSH URL is cloned with each user's Coder SSH key, so every user needs that
key (`coder publickey`) added to their account on the forge. Claude Code clones a plugin
repository the same way.

## Kubernetes access

The workspace runs in its own namespace, `coder-<owner>-<workspace>`, and its
`kubectl` can manage that namespace: deployments, jobs, services, secrets, the
lab resources, and `exec` into pods. It can't see other namespaces or the
cluster.

## Limits

- **No `ping`**: see below. Use `nc`, `curl` or `nslookup` to test connectivity.
- **Outbound:** the internet and Coder are reachable. With the recommended network policy,
  other workspaces, cluster services and the local network are not; your admin may allow more.
- **No Docker.** Build container images in CI.

> [!NOTE]
> **Why `ping` doesn't work**
>
> `ping` sends ICMP packets, which needs either a raw socket (the `NET_RAW` capability) or
> the kernel's unprivileged "ping sockets". Neither is available here, on purpose.
>
> - **`NET_RAW` is dropped.** Raw sockets let a process craft any packet: forge source
>   addresses, spoof ARP or DNS replies, or sniff traffic on the pod network. Coding agents run
>   in these workspaces with internet access, so the container doesn't get that power.
>   Kubernetes' own `restricted` security profile drops it for the same reason.
> - **Ping sockets can't be switched on.** They're controlled by the
>   `net.ipv4.ping_group_range` sysctl. Workspaces run in a user namespace (`hostUsers: false`)
>   for isolation, and with that enabled, widening the range stops the pod from starting at all.
>
> Everything else works: TCP, UDP, DNS and HTTP(S). To check that a host is reachable, try a
> port instead: `nc -zv host 443`, or `curl -sI https://host`.

## For admins

What the cluster and Coder need for this template (user namespaces, Pod Security, provisioner
permissions, namespace guardrails, egress, lab operators) is in `REQUIREMENTS.md`, in the
**Source Code** tab.
