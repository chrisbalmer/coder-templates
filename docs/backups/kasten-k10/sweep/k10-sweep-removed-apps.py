#!/usr/bin/env python3
"""Retire K10 restore points whose application namespace no longer exists.

K10 retention is count-based: each policy run pushes the oldest restore point
out of its tier. A deleted workspace gets no more runs, so its restore points
(local and exported) are never pushed out and stay in the catalog and in object
storage. Its local ones are already dead: their VolumeSnapshots and volume went
with the namespace.

Deletes go through the RestorePointContent, which makes K10 spawn a
RetireAction that removes the artifacts as well, including exported data.
Deleting the namespaced RestorePoint alone would not.

Dry run by default; pass --delete to retire.

    k10-sweep-removed-apps.py --policy coder-workspace-homes                 # older than 30 days
    k10-sweep-removed-apps.py --policy coder-workspace-homes --min-age-days 0

In a pod it talks to the API server with the ServiceAccount token. Elsewhere it
goes through `kubectl --raw`, with the current kubeconfig unless --kubeconfig
is given.
"""
import argparse
import json
import os
import ssl
import subprocess
import sys
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import datetime, timedelta, timezone

RPC_PATH = "/apis/apps.kio.kasten.io/v1alpha1/restorepointcontents"
SA_DIR = "/var/run/secrets/kubernetes.io/serviceaccount"
# Refuse to act on a namespace list that does not even contain K10's own
# namespace: an empty or truncated answer would make every app look removed.
SENTINEL_NAMESPACE = os.environ.get("K10_NAMESPACE", "kasten-io")


class InCluster:
    def __init__(self):
        host = os.environ["KUBERNETES_SERVICE_HOST"]
        port = os.environ.get("KUBERNETES_SERVICE_PORT", "443")
        self.base = f"https://{host}:{port}"
        with open(f"{SA_DIR}/token") as fh:
            self.token = fh.read().strip()
        self.ctx = ssl.create_default_context(cafile=f"{SA_DIR}/ca.crt")

    def call(self, method, path):
        req = urllib.request.Request(self.base + path, method=method,
                                     headers={"Authorization": f"Bearer {self.token}"})
        with urllib.request.urlopen(req, context=self.ctx, timeout=60) as resp:
            return json.load(resp)


class Kubectl:
    def __init__(self, kubeconfig):
        self.kubeconfig = kubeconfig

    def call(self, method, path):
        verb = {"GET": "get", "DELETE": "delete"}[method]
        kc = ["--kubeconfig", self.kubeconfig] if self.kubeconfig else []
        proc = subprocess.run(["kubectl", *kc, verb, "--raw", path],
                              capture_output=True, text=True)
        if proc.returncode:
            sys.exit(f"kubectl {verb} --raw {path}: {proc.stderr.strip()}")
        return json.loads(proc.stdout) if proc.stdout.strip() else {}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--policy", default="coder-workspace-homes",
                        help="k10.kasten.io/policyName to sweep (default: %(default)s)")
    parser.add_argument("--min-age-days", type=float, default=30,
                        help="only restore points older than this (default: %(default)s)")
    parser.add_argument("--delete", action="store_true",
                        help="delete the RestorePointContents (default: dry run)")
    parser.add_argument("--kubeconfig",
                        help="outside a pod only; default: kubectl's own")
    args = parser.parse_args()

    if os.path.exists(f"{SA_DIR}/token") and "KUBERNETES_SERVICE_HOST" in os.environ:
        api = InCluster()
    else:
        api = Kubectl(args.kubeconfig)

    namespaces = {ns["metadata"]["name"] for ns in api.call("GET", "/api/v1/namespaces")["items"]}
    if SENTINEL_NAMESPACE not in namespaces:
        sys.exit(f"namespace list ({len(namespaces)} items) lacks {SENTINEL_NAMESPACE}; refusing to sweep")

    selector = urllib.parse.quote(f"k10.kasten.io/policyName={args.policy}")
    rpcs = api.call("GET", f"{RPC_PATH}?labelSelector={selector}")["items"]
    cutoff = datetime.now(timezone.utc) - timedelta(days=args.min_age_days)

    stale = defaultdict(list)
    kept_young = 0
    for rpc in rpcs:
        app_ns = rpc["metadata"].get("labels", {}).get("k10.kasten.io/appNamespace")
        if not app_ns or app_ns in namespaces:
            continue
        created = datetime.fromisoformat(rpc["metadata"]["creationTimestamp"].replace("Z", "+00:00"))
        if created > cutoff:
            kept_young += 1
            continue
        stale[app_ns].append((rpc["metadata"]["creationTimestamp"], rpc["metadata"]["name"]))

    total = sum(len(v) for v in stale.values())
    print(f"policy={args.policy} restorepointcontents={len(rpcs)} "
          f"removed-app candidates={total} younger-than-{args.min_age_days:g}d={kept_young}")
    for app_ns in sorted(stale):
        print(f"\n{app_ns}")
        for created, name in sorted(stale[app_ns]):
            print(f"  {created}  {name}")

    if not total:
        return 0
    if not args.delete:
        print("\nDry run: pass --delete to retire these.")
        return 0

    for items in stale.values():
        for _, name in items:
            api.call("DELETE", f"{RPC_PATH}/{name}")
    print(f"\nDeleted {total} RestorePointContents. K10 retires their artifacts asynchronously"
          " (retireactions.actions.kio.kasten.io).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
