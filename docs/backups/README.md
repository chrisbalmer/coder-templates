# Backing up workspace homes

The `k8s-stack` template doesn't back anything up. Each workspace keeps its home
directory on one PersistentVolumeClaim, `home`, in its own namespace
(`coder-<owner>-<workspace>`). That volume is the only state worth protecting:
Terraform rebuilds everything else in the namespace on the next start, and the
lab databases are scratch.

This page describes how the reference setup protects `home` with
[Veeam Kasten K10](https://docs.kasten.io/), and how to restore it. The examples
are in [`kasten-k10/`](kasten-k10/). It was tested with K10 9.0.6,
Capsule 0.14.6 and Longhorn CSI snapshots.

## What the policy does

[`kasten-k10/policy.yaml`](kasten-k10/policy.yaml) is a single K10 Policy for all
workspaces:

- **It selects namespaces by label, not by name.** Workspace namespaces come and
  go with workspaces, so a list of names would go stale on the next create. The
  example matches `coder.io/tenant: "true"`, the label
  [REQUIREMENTS.md](../../templates/k8s-stack/REQUIREMENTS.md) asks every workspace
  namespace to carry. A namespace created after the policy is picked up at the
  next run with no edit. K10 also matches the selector against Deployment and
  StatefulSet labels, so don't put that label on workloads elsewhere.
- **It captures `home` only,** through `includeResources`. The restore point then
  holds the PVC, its data and its StorageClass, and nothing the template recreates.
- **It runs daily, not hourly.** If your CSI driver keeps snapshots inside the
  volume (Longhorn does), each retained snapshot pins blocks that the filesystem
  has already freed. Workspace homes churn (builds, package caches), so hourly
  snapshots inflate volume usage quickly.
- **It exports every snapshot to object storage** (a K10 location profile).
  Local snapshots protect against mistakes; the export is what survives losing the
  volume, the workspace or the cluster.

## What it can't do

- **A deleted workspace keeps no local restore points.** Its snapshots go with
  the namespace and the volume. Only the exports remain, listed under the old
  namespace name.
- **Retention never retires a deleted workspace's restore points.** K10
  retention is count-based: each policy run pushes the oldest restore point out
  of its tier. A deleted workspace gets no more runs, so its points stay in the
  catalog and in object storage until something deletes them. The sweep job in
  [Cleaning up](#cleaning-up) does, after a grace period.

## Restoring

Two things break the obvious approach, which is a K10 RestoreAction straight
into the workspace's namespace with `overwriteExisting: true`.

**K10 restores by moving a PersistentVolume.** It builds the restored volume in
its own namespace, then moves it into the target by creating a PVC pre-bound to
it with `spec.volumeName`. Capsule refuses a pre-bound PVC in a tenant namespace
unless the PV carries `capsule.clastix.io/tenant: <tenant>`, to stop one tenant
mounting another's volume, and K10 doesn't add that label. With Capsule, every
K10 restore into a workspace namespace fails at this step: from an export, from a
local snapshot, even into the same namespace. Other tenancy controllers may
behave differently.

**`overwriteExisting` deletes the existing PVC before it restores.** If the
restore then fails, the workspace has no home. And if the restore point is a
*local* snapshot stored inside that volume, deleting the PVC destroys the
snapshot the restore is reading from. A safety copy taken before a restore must
be an export.

So restore in two stages: into a scratch namespace first, then into the workspace.

### 1. Restore into a scratch namespace

Use a namespace that your tenancy controller doesn't manage. In the reference
setup, that means no `coder-` prefix and no tenant labels.

```bash
kubectl create namespace workspace-restore
kubectl -n <workspace-namespace> get restorepoints.apps.kio.kasten.io
```

Exported restore points carry the label
`k10.kasten.io/exportType=portableAppData`. Edit
[`kasten-k10/restore-to-scratch.yaml`](kasten-k10/restore-to-scratch.yaml) and
apply it. The RestoreAction must live in its `targetNamespace`, and `profile` is
only needed for an exported restore point. A local restore point also works here
while the workspace still exists, and it's quicker.

Mount the restored `home` read-only in a throwaway pod and check it before going
any further.

### 2a. A few files: copy them across

With the workspace running, run a pod in the scratch namespace that mounts the
restored PVC (as uid 1000), and stream from it:

```bash
kubectl -n workspace-restore exec restore-source -- tar -C /restore -cf - path/one path/two \
  | kubectl -n <workspace-namespace> exec -i <workspace-pod> -c dev -- tar -C /home/coder -xf -
```

This merges into the existing home and goes through your machine, so use it for
files, not whole homes.

### 2b. The whole home: hand the volume over

This swaps `home` for the restored volume itself, with no copy. Labelling the PV
for the tenant is the deliberate admin step that Capsule asks for.

1. Stop the workspace. To restore a **deleted** workspace, recreate it first with
   the same owner and name, so the provisioner builds the namespace with all its
   guardrails, then stop it. Don't let K10 create the namespace.
2. Release the PV from the scratch namespace, and keep it:

   ```bash
   PV=$(kubectl -n workspace-restore get pvc home -o jsonpath='{.spec.volumeName}')
   kubectl patch pv "$PV" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'   # before deleting the PVC
   kubectl -n workspace-restore delete pvc home
   kubectl patch pv "$PV" --type json -p '[{"op":"remove","path":"/spec/claimRef"},
     {"op":"add","path":"/metadata/labels","value":{"capsule.clastix.io/tenant":"<tenant>"}}]'
   ```

   If the PV already has labels, add the one label with the path
   `/metadata/labels/capsule.clastix.io~1tenant` rather than replacing the map.
3. Replace the workspace's `home`. This deletes the current one, so export it
   first if it holds anything you want. Then apply
   [`kasten-k10/home-prebound-pvc.yaml`](kasten-k10/home-prebound-pvc.yaml) with
   the PV name and capacity filled in, wait for `Bound`, and set the reclaim policy
   back:

   ```bash
   kubectl -n <workspace-namespace> delete pvc home --ignore-not-found
   kubectl apply -f home-prebound-pvc.yaml
   kubectl -n <workspace-namespace> wait --for=jsonpath='{.status.phase}'=Bound pvc/home
   kubectl patch pv "$PV" -p '{"spec":{"persistentVolumeReclaimPolicy":"Delete"}}'
   ```

   Capsule adds a tenant selector to the PVC as it's admitted; that's expected.
4. Start the workspace. The template finds `home` by name and leaves it alone
   (`ignore_changes = all`). The build log reports drift on it, but nothing changes.

Delete the scratch namespace when you're done.

## Cleaning up

[`kasten-k10/sweep/`](kasten-k10/sweep/) is a nightly CronJob that retires the
restore points of deleted workspaces once they are older than a grace period
(30 days in the example). That grace period is your window for restoring a
deleted workspace. It runs
[`k10-sweep-removed-apps.py`](kasten-k10/sweep/k10-sweep-removed-apps.py), which:

- finds restore points of the policy whose namespace no longer exists;
- refuses to act if the namespace list doesn't include K10's own namespace,
  since an empty or truncated list would make every workspace look deleted;
- deletes their **RestorePointContents**, not the namespaced RestorePoints.
  Deleting the content starts a K10 RetireAction, which also removes the exported
  data from object storage; deleting a RestorePoint alone doesn't.

Its RBAC is limited to listing namespaces, and listing and deleting
RestorePointContents. Set the policy name and grace period in `cronjob.yaml`,
then `kubectl apply -k docs/backups/kasten-k10/sweep`. The script also runs by
hand from a workstation, as a dry run unless you pass `--delete`:

```bash
docs/backups/kasten-k10/sweep/k10-sweep-removed-apps.py --policy coder-workspace-homes --min-age-days 0
```

Restore points from a manual run of the policy are never retired by its
retention either. Set `spec.expiresAt` on the RunAction so they expire.
