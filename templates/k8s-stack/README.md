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
(`gh`, `tea`, `fj`), plus `nc` for network checks. The image can't be changed after the workspace
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

Install tools with `sudo apt-get install`, or into your home directory. Changes
outside `/home/coder` are lost when the workspace stops.

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
