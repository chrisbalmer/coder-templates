locals {
  ns_raw = lower("coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}")
  # DNS label limit is 63; owner (<=32) + workspace (<=32) can exceed it.
  # Truncate deterministically and keep it unique with the workspace ID.
  ns = length(local.ns_raw) > 63 ? "${substr(local.ns_raw, 0, 54)}-${substr(data.coder_workspace.me.id, 0, 8)}" : local.ns_raw
}

# Unguarded: survives stop. Capsule stamps the tenant labels, PSA labels,
# ResourceQuota, LimitRange, NetworkPolicy and owner RoleBindings on create.
resource "kubernetes_namespace_v1" "ws" {
  metadata {
    name = local.ns
    labels = {
      "coder.io/owner"     = lower(data.coder_workspace_owner.me.name)
      "coder.io/workspace" = lower(data.coder_workspace.me.name)
    }
  }

  lifecycle {
    # Capsule owns the rest of the labels; don't fight it over them.
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

# Capsule's RoleBindings land about 1s after the namespace; a namespaced create
# in that window gets 403. Everything namespaced
# depends on this, not on the namespace directly.
resource "time_sleep" "capsule_rbac" {
  depends_on      = [kubernetes_namespace_v1.ws]
  create_duration = "5s"
}
