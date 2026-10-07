# k8s-desktop: cluster requirements

What a Kubernetes cluster and a Coder deployment need before this template works. It's
written for the person running the cluster; the template's user-facing docs are in
`README.md`.

This template runs on the same platform as [`k8s-stack`](../k8s-stack/REQUIREMENTS.md): one
namespace per workspace (`coder-<owner>-<workspace>`), user namespaces, Pod Security
`baseline`, and the same tenancy guardrails. **Set that up first, following `k8s-stack`'s
requirements.** This file lists only what's different.

## What the template creates

Per workspace namespace: a Deployment running the desktop image, a `home` PVC, the agent token
Secret and an `ssh-known-hosts` ConfigMap. Unlike `k8s-stack` it creates **no**
ServiceAccount, Role or lab resources, and the pod mounts **no** Kubernetes API token.

## Differences from k8s-stack

| Area | k8s-stack | k8s-desktop |
|---|---|---|
| Provisioner rights | `admin` plus the three lab operators' API groups | `admin` is enough; no lab API groups needed |
| Kubernetes API from the workspace | Workspace ServiceAccount, egress to the API server on 6443 | None: `automountServiceAccountToken: false`, so no API egress is needed |
| Capabilities | Drops `NET_RAW` and `MKNOD` | Drops `MKNOD`; drops `NET_RAW` unless the user turns on **Raw sockets** (on in the Kali preset). `NET_RAW` is in the default set that `baseline` allows, and with `hostUsers: false` it only reaches the pod's own network namespace |
| Pod sysctls | None | `net.ipv4.ping_group_range = 0 65535`, so `ping` works without `NET_RAW`. The range must stay within the GIDs the pod's user namespace maps (0–65535); a wider one makes runc fail the sandbox (`invalid argument`). It's a Kubernetes *safe* sysctl: PSA `baseline` allows it and the kubelet accepts it by default, scoped to the pod's own network namespace |
| `/dev/shm` | Runtime default (64 MiB) | 1 GiB memory-backed `emptyDir`, counted against the memory limit |
| Requests | 250m CPU, 512 MiB | 500m CPU, 1 GiB |
| Quota (largest workspace) | 8 CPU, 16 GiB plus labs | 8 CPU, 16 GiB, one PVC (up to 100 GiB) |
| Images | `base`, `cortex`, `infra`, `golang`, `app` | `ubuntu-desktop`, `kali-desktop` |

## Wildcard access URL

The desktop is a [KasmVNC](https://kasmweb.com/kasmvnc) web client that Coder proxies. It works
best on its own subdomain, which needs a **wildcard access URL** on the deployment
(`CODER_WILDCARD_ACCESS_URL`, for example `*.coder.example.com`, with DNS and a certificate to
match). Without one, set the template variable `app_subdomain = false`; the module then patches
KasmVNC to work on a path.

There's no VNC password: KasmVNC listens on `127.0.0.1` inside the pod, and access is through
the Coder session, shared with the owner only.

## Egress

The workspace needs the same egress as `k8s-stack` (DNS, the Coder access URL, the internet),
except the Kubernetes API server. The images ship KasmVNC, so nothing is downloaded at start.
With an image that lacks it, the module downloads it from `github.com` and runs `apt-get`
against the distribution's mirrors on every start.

> [!WARNING]
> A security lab is still a pod on your cluster. Keep the `k8s-stack` egress fence (no LAN, no
> other namespaces, no cluster services) on these namespaces. The fence is what stops a tool or
> a sample in a Kali workspace from reaching your network.

## Backups

Backups that select workspace namespaces by label (see [`docs/backups/`](../../docs/backups/README.md))
also back up desktop homes. A Kali workspace's home can hold malware samples and tool output;
exclude those namespaces or the user's sample directory if your backup target scans for
malware.

## Verify

Create a workspace from each preset and check:

- the **KasmVNC** app opens an Xfce desktop in the browser tab;
- `sudo -n true` works;
- `ls /var/run/secrets/kubernetes.io` fails (no API token);
- `ping -c1 1.1.1.1` fails with the Ubuntu preset, and works with the Kali preset (Raw sockets
  on) if your egress allows ICMP.
