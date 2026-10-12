# Linux Desktop on Kubernetes

A Linux desktop in your browser. Each workspace runs an Xfce desktop in a container on
Kubernetes, and the **KasmVNC** app opens it in a browser tab. Use it for graphical
tools, and for Kali's security tools with or without the desktop. For terminal or VS Code
development, use **Linux Stack on Kubernetes** instead.

| Preset | Image | Desktop | Size | Raw sockets |
|---|---|---|---|---|
| Ubuntu desktop (default) | `ubuntu-desktop` | on | 4 CPU / 8 GiB | off |
| Kali security lab | `kali-desktop` | on | 4 CPU / 8 GiB | on |
| Kali headless | `kali-desktop` | off | 4 CPU / 8 GiB | on |

Both run Xfce with Firefox and passwordless `sudo`. The Ubuntu image also has the CLI tools
of the headless images (git, Python, uv, kubectl, `gh`). The image can't be changed after the
workspace is created. CPU, memory, the repo, **Desktop**, **Raw sockets** and the CLI login
can. **Desktop** off leaves out the KasmVNC app; everything else, including the image, stays
the same, so a Kali workspace can switch between the two with a restart.

## Using the desktop

Open **KasmVNC** from the workspace page. It opens in its own browser tab; there's no
password, because only you can reach it through Coder. The KasmVNC side panel (the arrow
on the left edge) has the clipboard, file upload and download, and display settings.
Closing the tab leaves the desktop running.

The terminal, SSH and port forwarding work as in any Coder workspace (`coder ssh`,
`coder port-forward`).

## What survives

- **Stop:** your home directory (`/home/coder`) is kept, including your desktop settings.
  The container is removed.
- **Delete:** everything goes, including the home directory.
- **Changes outside `/home/coder` are lost when the workspace stops.** That includes
  anything you `sudo apt-get install`. For tools you want to keep, install them into your
  home directory (`uv tool install`, `pipx`, a release binary in `~/.local/bin`), or ask for
  them to be added to the image.
- **Backups:** the template backs nothing up. Your home directory is protected only if your
  administrator backs up the `home` volume. Push work you care about.

## Autostop

A workspace stops **8 hours after it starts**. While you're using it, each bit of activity
pushes the stop time back to at least an hour away: an open KasmVNC tab, a terminal or SSH
session, or a port forward.

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

## Kali security lab

The Kali presets are for security work and learning: reverse engineering, static malware
analysis and tool practice. They work well for:

- **Reverse engineering and static analysis** of samples you don't run: Ghidra, radare2,
  rizin, YARA, Python's `pefile`, and Kali's reverse-engineering and forensics tools.
- **Password, crypto and stego challenges**, with Kali's tools for each.
- **Web and pwn challenges** whose targets are on the internet: Kali's web and
  exploitation tools, and `pwntools` (`nc host port` to a CTF server works).

It does **not** support:

- **VPN-based labs** (Hack The Box, TryHackMe, OffSec): there's no `/dev/net/tun` and no
  `NET_ADMIN`, so OpenVPN and WireGuard can't run. Use the platform's browser-based attack box.
- **Running Windows malware.** The container is Linux; there's no Windows VM. Analyse
  Windows samples statically here, and run them only in an isolated Windows VM elsewhere.
- **Your local network.** With the recommended network policy, only the internet is reachable.

### Reverse-engineering tools

Besides Kali's tool groups, the image has:

| Tool | For |
|---|---|
| `gdb` with GEF | GEF loads in every `gdb`, including pwntools' `gdb.attach`. `GEF_DISABLE=1 gdb ...` gives plain gdb, for scripted runs |
| `ltrace`, `strace` | Library and system call tracing (`ltrace` shows nothing on binaries built with CET/IBT) |
| `bpftool`, `llvm-objdump` | Dumping and disassembling eBPF programs and maps |
| `ncat` | `ncat --ssl host port` for TLS-wrapped services |
| `pycdc`, `pycdas`, `pyinstxtractor-ng` | Unpacking PyInstaller bundles and decompiling `.pyc` files up to Python 3.13 |
| `dotnet`, `ilspycmd` | Decompiling .NET assemblies (`ilspycmd -p -o out/ app.dll`) |
| `analyzeHeadless` | Ghidra's headless analyzer |
| `ghidra-mcp` | Ghidra as an MCP server, for an AI agent (below) |
| `uv` and the `re` Python environment | `python3` is `/opt/venvs/re`, with angr, z3, pyghidra and pyghidra-mcp, plus Kali's pwntools, capstone, unicorn and keystone |

Packages you add to the Python environment (`uv pip install ...`) are lost when the workspace
stops, like anything outside `/home/coder`. For extras that persist, make your own environment
in your home that still sees these: `uv venv --system-site-packages ~/venv`.

`re-check-tools` checks all of it: tools on the PATH, the environment a new shell gets, the
Python imports, `analyzeHeadless`, `ghidra-mcp` and `ilspycmd`. It takes about a minute
(`--quick` skips Ghidra). Run it in the workspace, or from your machine:
`ssh <workspace>.coder re-check-tools`.

### Ghidra for an AI agent (MCP)

`ghidra-mcp` runs headless Ghidra as an MCP server over stdio, so an agent such as Claude Code
can decompile, search and annotate binaries. Run the agent on your machine and the server in the
workspace, over SSH (after `coder config-ssh`):

```sh
claude mcp add ghidra -- ssh <workspace>.coder ghidra-mcp
```

- The Ghidra project is `~/re/ghidra-projects/re`. Put binaries in `~/re/bins` and ask the agent
  to import them, or pass paths: `ssh <workspace>.coder ghidra-mcp ~/re/bins/sample`.
- Ghidra locks a project while it's open. If an earlier server is still running on the same
  project (say an SSH session dropped), `ghidra-mcp` stops it first: the newest session wins. To
  run two at once, give one its own project: `GHIDRA_MCP_PROJECT_NAME=other ghidra-mcp`.
- Logs are in `~/.cache/ghidra-mcp/`; `latest.log` is the newest. Look there when the agent
  says the connection closed.
- Startup takes about 10 seconds, while Ghidra loads.

### Handling samples

- Keep samples in one directory, such as `~/samples`, and store them zipped with a password
  (`infected` is the convention). Unzip only to analyse.
- Don't run a sample in this workspace, even a Linux one, unless the exercise expects it.
- Your home directory may be backed up and scanned by your administrator's tools. Tell them
  before storing live malware.

### Raw sockets

**Raw sockets** keeps the `NET_RAW` capability for tools that build their own packets, such as
`nmap -sS`, `tcpdump` and `scapy`; run them with `sudo`. It's on in the Kali preset and off in
the Ubuntu preset; change it in the workspace settings and restart. `ping` works on Kali without
it or `sudo`. The Ubuntu image has no usable `ping`; use `curl` or `nc` to test reachability. It only reaches the workspace's own network interface, and the
network policy still applies.

## Dotfiles

The **Dotfiles URL** setting is applied with `coder dotfiles` on every start. It's
pre-filled with your admin's default (out of the box,
`git@github.com:<your Coder username>/dotfiles.git`). Change it, or clear it to skip
dotfiles. An SSH URL uses your Coder SSH key (`coder publickey`).

## Git identity

Set your name and email in your own git config, ideally in your dotfiles. If you set
nothing, commits use your Coder name and login email: the template writes those to
`/etc/gitconfig` as a fallback on every start.

## The coder CLI

The `coder` CLI is installed in the workspace but not logged in. **Log in the coder CLI**
(`coder_login`, off by default, changeable any time) puts a Coder session token for your
account in the workspace's environment (`CODER_SESSION_TOKEN`, with `CODER_URL`), so commands
like `coder list` or `coder ssh <other workspace>` work straight away. The token can do anything
your account can, and every process in the workspace can read it, AI agents included. A new one
is made on every start and deleted when the workspace stops. Leave it off unless you use the CLI
here often. Otherwise run `coder login` when you need it: that token stays in the CLI's config
instead of the environment.

## Limits

- **No Kubernetes access.** The workspace has no `kubectl` credentials for the cluster.
- **No GPU.** The desktop is software-rendered; 3D and video are slow.
- **No Docker**, no sound, and no USB devices. A sample or project that ships a Dockerfile
  can't be built or run here; read the Dockerfile for the environment it expects.

## For admins

What the cluster and Coder need for this template is in `REQUIREMENTS.md`, in the
**Source Code** tab. It builds on `k8s-stack`'s requirements.
