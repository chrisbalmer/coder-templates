# k8s-stack: cluster requirements

What a Kubernetes cluster and a Coder deployment need before this template works. It's
written for the person running the cluster; the template's user-facing docs are in
`README.md`.

The template gives **every workspace its own namespace**, `coder-<owner>-<workspace>`. It
creates the namespace, a workspace Deployment, a home PVC, a ServiceAccount with a Role
scoped to that namespace, and optional throwaway lab databases (Postgres, MinIO, MySQL)
run by operators. Most of what follows is about letting Coder's provisioner create
namespaces **safely**. It needs rights that are powerful when left unscoped.

## Checklist

| # | Requirement | Required? |
|---|---|---|
| 1 | Kubernetes with user namespaces (`hostUsers: false`) working | Yes |
| 2 | amd64 worker nodes | Yes, or edit `nodeSelector` |
| 3 | A ReadWriteOnce StorageClass | Yes |
| 4 | Pod Security `baseline` (not `restricted`) in workspace namespaces | Yes |
| 5 | Coder 2.37+ and a provisioner whose Kubernetes identity has the permissions below | Yes |
| 6 | Tenancy guardrails on `coder-*` namespaces: quota, network policy, a name/label fence | Strongly recommended |
| 7 | Egress from workspace namespaces to the Coder URL, the Kubernetes API and the internet | Yes |
| 8 | CloudNativePG, MinIO Operator, MOCO (plus cert-manager) | Only for the matching lab toggle |
| 9 | coder-logstream-kube ≥ 0.0.14 watching all namespaces | Optional |

## 1. Kubernetes and nodes

- **User namespaces.** The workspace pod sets `hostUsers: false`, so container root maps to an unprivileged uid on the node. That needs the `UserNamespacesSupport` feature (on by default from Kubernetes 1.33), a container runtime that supports it (containerd 2.x), and a kernel with idmapped mounts for your volume types (Linux 6.3 or later is safe). Tested on Kubernetes 1.36 with Talos and Longhorn: files on the home volume stay owned by uid 1000.
- **amd64 nodes.** The pod has `nodeSelector: kubernetes.io/arch=amd64`. The images are multi-arch (amd64 and arm64); remove the selector in `workspace.tf` if you want arm64 nodes.
- **Seccomp.** The container sets `seccompProfile: RuntimeDefault`, so the runtime must provide a default profile (standard in containerd).

Test it with a pod before you go further:

```bash
kubectl run userns-test --rm -it --restart=Never --image=busybox \
  --overrides='{"spec":{"hostUsers":false}}' -- cat /proc/self/uid_map
# Expect something like "0  <large number>  65536", not "0  0  4294967295"
```

## 2. Storage

A **ReadWriteOnce** StorageClass for the home volume (`/home/coder`, 1–100 GiB, chosen per workspace) and the lab volumes (1 Gi each). A reclaim policy of `Delete` is recommended: deleting a workspace should delete its data.

By default the cluster's **default StorageClass** is used. Set the template variable `storage_class` to pin a class for every workspace, or leave it empty and list classes in `storage_class_options` to let users pick one when they create a workspace (the first is the default). Pass them on every push, for example through `CODER_TEMPLATE_VARIABLES` (see the repository README).

## 3. Pod Security

Workspace namespaces must allow the **`baseline`** Pod Security Standard. `restricted` breaks the workspace:

- The images give the `coder` user (uid 1000) passwordless `sudo`, and the template uses it.
- `restricted` requires `allowPrivilegeEscalation: false`, which sets `no_new_privs`, and setuid `sudo` then can't become root.

The container drops `NET_RAW` and `MKNOD` (so there's no `ping`), and nothing is privileged, so `baseline` is enough. Setting `warn`/`audit` to `restricted` is fine; it only produces warnings. The lab operators' pods run under `baseline` too.

## 4. Coder and the provisioner

- **Coder 2.37 or later**: workspace presets, and the `coder` Terraform provider `~> 2.18`. The provisioner's Terraform must be **1.15 or later**.
- **A provisioner with its own Kubernetes identity** (recommended): an external provisioner in its own namespace, running as a dedicated ServiceAccount, with coderd's own workspace permissions removed. External provisioners need Coder Premium. With the built-in provisioners, coderd's ServiceAccount needs everything below instead.
- **Dotfiles default.** The template variable `default_dotfiles_uri` pre-fills the users' Dotfiles URL. `{username}` becomes the Coder username; the default is `git@github.com:{username}/dotfiles.git`, which assumes Coder usernames match GitHub usernames. Set your own pattern, or `""` for none, through `CODER_TEMPLATE_VARIABLES`.
- **Registry icons.** The template uses icons Coder ships (`/icon/*`, `/emojis/*`).

### Provisioner permissions

| Scope | Permission | Why |
|---|---|---|
| Cluster | `create` namespaces | One namespace per workspace |
| Cluster | `get` namespaces | Terraform reads the namespace straight back after creating it |
| Cluster | `get`, `list`, `watch` `customresourcedefinitions` | `kubernetes_manifest` (used for the Deployment and the labs) resolves every object's type through the CRDs at plan time. Without this, **every** plan fails with `cannot list resource "customresourcedefinitions"`. |
| Each workspace namespace | `admin`, plus `*` on CNPG `clusters`, MinIO `tenants` and MOCO `mysqlclusters` | Creates the workspace objects and the lab resources. Kubernetes only lets it grant the workspace Role permissions it holds itself, so it must hold the lab permissions too. |
| Each workspace namespace | `delete` the namespace | Workspace deletion removes the namespace and everything in it |

Grant `create` namespaces cluster-wide **only behind the guardrails in section 5**. On its own it lets the provisioner create any namespace.

The namespace-scoped rights have to exist **as soon as the namespace does**. The template waits 5 seconds (`time_sleep.capsule_rbac`) after creating the namespace, so a controller that stamps RoleBindings into new namespaces has time to act. [Capsule](https://projectcapsule.dev/) with the provisioner as a Tenant owner does exactly that.

## 5. Guardrails for `coder-*` namespaces (strongly recommended)

The reference setup is a Capsule Tenant (`coder`) owned by the provisioner's ServiceAccount, plus a ValidatingAdmissionPolicy. Any mechanism that achieves the same result works.

**Namespace fence.** The provisioner may only create, update or delete namespaces named `coder-*`. The reference setup enforces this twice: Capsule's `forceTenantPrefix`, and a ValidatingAdmissionPolicy on the provisioner's username. The policy also requires the tenant labels, so a namespace can't be created unguarded while Capsule is down.

**Per-namespace labels.** Each workspace namespace needs `coder.io/tenant: "true"`:
- the egress policy and the operators' network policies select namespaces by it;
- the pod's anti-affinity uses it to spread workspaces across nodes.

The template doesn't set this label itself; the tenancy controller does.

**ResourceQuota.** It must fit the largest workspace with every lab turned on:

| | Workspace (max) | 3 labs | Total at least |
|---|---|---|---|
| CPU limits | 8 | 3 | 11 |
| Memory limits | 16 Gi | 3 Gi | 19 Gi |
| CPU requests | 0.25 | 0.3 | 0.55 |
| Memory requests | 0.5 Gi | 1 Gi | 1.5 Gi |
| PVCs | 1 | 3 | 4 |
| Pods | 1 | 3 (plus operator helpers) | about 6 |

The reference setup uses limits of 16 CPU / 32 Gi, requests of 8 / 16 Gi, 20 pods and 10 PVCs.

**LimitRange.** Optional. The template sets explicit requests and limits on everything it creates.

**Ingress NetworkPolicy.** Allow the same namespace, the three operators' namespaces, and Coder's namespace (coderd opens direct connections to agents, and otherwise falls back to its relay). Nothing else needs to reach a workspace: the agent dials out.

## 6. Egress from workspace namespaces

Workspace pods need:

| Destination | Why |
|---|---|
| Cluster DNS | Everything |
| The Coder access URL | The agent connects out to coderd (HTTPS, WebSocket) |
| Kubernetes API server, port **6443 only** | `kubectl` and the lab startup script run as the workspace ServiceAccount. Allowing the API server's whole node exposes etcd and the node API; scope it to the API port. |
| The internet (HTTPS at least) | Package installs, git, registries, AI APIs |
| High UDP ports to private ranges | Optional: direct Coder connections (otherwise the relay is used) |

Recommended denies: other namespaces (so one workspace can't reach another's databases), cluster services, and your LAN. The reference setup does this with a Cilium clusterwide policy selecting `coder.io/tenant=true` namespaces, plus the tenancy controller's same-namespace NetworkPolicy for traffic to the labs.

## 7. Images and registries

The pod pulls one image per preset from **`ghcr.io/chrisbalmer/coder-images-<name>`** (`base`, `cortex`, `infra`, `golang`, `app`), pinned to exact versions in `locals.images` in `main.tf`. To pull from a mirror that carries the same names and versions, set the template variable `image_registry` (default `ghcr.io/chrisbalmer`).

With the labs on, the operators pull:

| Lab | Images |
|---|---|
| Postgres | `ghcr.io/cloudnative-pg/postgresql:18.4` |
| MinIO | The template variable `lab_minio_image` (default `quay.io/minio/minio:RELEASE.2025-04-08T15-41-24Z`), plus the operator's sidecar (`quay.io/minio/operator-sidecar`) |
| MySQL | `ghcr.io/cybozu-go/moco/mysql:8.4.10`, plus `ghcr.io/cybozu-go/moco-agent` |

If you restrict registries per namespace (Capsule's `containerRegistries`, Kyverno and so on), allow **`ghcr.io`** and **`quay.io`**.

The MinIO image is set explicitly because MinIO Operator 7.1 otherwise defaults to Docker Hub's `minio/minio`.

> [!WARNING]
> MinIO, Inc. no longer distributes the community server: `quay.io/minio/minio` and `docker.io/minio/minio` refuse anonymous pulls, so the default only works on nodes that already have it cached. Build or copy the image into a registry you control (the source is still on GitHub under AGPLv3), keep the same `RELEASE.*` tag, and set `lab_minio_image` to it, for example through `CODER_TEMPLATE_VARIABLES`. If you restrict registries per namespace, allow that registry too. The operator sidecar (`quay.io/minio/operator-sidecar`) is still pullable but may follow.

## 8. Lab operators (optional)

Each lab toggle only works if its operator is installed. The workspace Role and the provisioner's rights mention all three API groups, but a lab object is only created when its toggle is on.

| Toggle | Operator | Resource | Notes |
|---|---|---|---|
| `lab_postgres` | [CloudNativePG](https://cloudnative-pg.io/) | `postgresql.cnpg.io/v1` `Cluster` | One instance, PDB disabled |
| `lab_minio` | [MinIO Operator](https://min.io/docs/minio/kubernetes/upstream/) 7.1 | `minio.min.io/v2` `Tenant` | Its data volume survives stop; it's reused on the next start |
| `lab_mysql` | [MOCO](https://cybozu-go.github.io/moco/) 0.27+ | `moco.cybozu.com/v1beta2` `MySQLCluster` | **Needs cert-manager.** The template caps `innodb_log_file_size` at 50M, because MOCO's 800M default fills the 1 Gi volume. |

The operators must be able to reach pods in `coder-*` namespaces (their own egress, plus the namespace ingress policy in section 5): CNPG's instance manager on port 8000, the MinIO Operator to the tenant, and MOCO to its agent (port 9080) and mysqld (port 3306).

## 9. Pod events in build logs (optional)

[coder-logstream-kube](https://github.com/coder/coder-logstream-kube) streams Kubernetes events (scheduling, image pulls, crashes) into workspace startup logs. For this template:

- run **v0.0.14 or later**: the template passes `CODER_AGENT_TOKEN` from a Secret (`coder-agent-token`), not inline, and older versions only read inline tokens;
- set `namespaces: []` (watch all), because workspace namespaces are created dynamically;
- that makes the chart grant `get` on **all** Secrets. Narrow the rule to `resourceNames: ["coder-agent-token"]`, for example with a Flux or Kustomize post-render patch.

## Verify

Using your provisioner's identity:

```bash
SA=system:serviceaccount:coder-provisioner:coder-provisioner   # adjust to yours
kubectl auth can-i create namespaces --as=$SA                    # yes
kubectl auth can-i list customresourcedefinitions --as=$SA       # yes
kubectl create namespace coder-probe --as=$SA                    # allowed
kubectl create namespace not-coder --as=$SA                      # denied (fence)
kubectl get ns coder-probe --show-labels                         # coder.io/tenant=true, PSA baseline
kubectl -n coder-probe get resourcequota,limitrange,networkpolicy,rolebinding
kubectl delete namespace coder-probe --as=$SA
```

Then push the template, create a workspace from the **General** preset, and check that `sudo -n true` works and that `ping` fails, which it should. Then turn on each lab you need and restart.
