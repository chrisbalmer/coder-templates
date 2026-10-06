# Linux Desktop on Kubernetes

A Linux desktop in your browser. Each workspace runs an Xfce desktop in a container on
Kubernetes, and the **KasmVNC** app opens it in a browser tab. Use it for graphical
tools. For terminal or VS Code development, use **Linux Stack on Kubernetes** instead.

| Preset | Image | Size | Raw sockets |
|---|---|---|---|
| Ubuntu desktop (default) | `ubuntu-desktop` | 4 CPU / 8 GiB | off |
| Kali security lab | `kali-desktop` | 4 CPU / 8 GiB | on |

Both run Xfce with passwordless `sudo`. The Ubuntu image also has the CLI tools of the
headless images (git, Python, uv, kubectl, `gh`). The image can't be changed after the
workspace is created. CPU, memory, the repo and **Raw sockets** can.

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

## Kali security lab

The Kali preset is for security learning: CTFs, static malware analysis and tool practice.
It works well for:

- **Reverse engineering and static analysis** of samples you don't run.
- **Web, crypto, forensics and pwn challenges** whose targets are on the internet
  (for example `nc host port` to a CTF server).

It does **not** support:

- **VPN-based labs** (Hack The Box, TryHackMe, OffSec): there's no `/dev/net/tun` and no
  `NET_ADMIN`, so OpenVPN and WireGuard can't run. Use the platform's browser-based attack box.
- **Running Windows malware.** The container is Linux; there's no Windows VM. Analyse
  Windows samples statically here, and run them only in an isolated Windows VM elsewhere.
- **Your local network.** With the recommended network policy, only the internet is reachable.

### Handling samples

- Keep samples in one directory, such as `~/samples`, and store them zipped with a password
  (`infected` is the convention). Unzip only to analyse.
- Don't run a sample in this workspace, even a Linux one, unless the exercise expects it.
- Your home directory may be backed up and scanned by your administrator's tools. Tell them
  before storing live malware.

### Raw sockets

**Raw sockets** keeps the `NET_RAW` capability, so `nmap -sS`, `tcpdump`, `scapy` and `ping`
work. It's on in the Kali preset and off in the Ubuntu preset; change it in the workspace
settings and restart. It only reaches the workspace's own network interface, and the
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

## Limits

- **No Kubernetes access.** The workspace has no `kubectl` credentials for the cluster.
- **No GPU.** The desktop is software-rendered; 3D and video are slow.
- **No Docker**, no sound, and no USB devices.

## For admins

What the cluster and Coder need for this template is in `REQUIREMENTS.md`, in the
**Source Code** tab. It builds on `k8s-stack`'s requirements.
