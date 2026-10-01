# Per-workspace identity, scoped to its own namespace. The provisioner can only
# grant what it holds (admin + coder-lab-operators), so core/apps/batch verbs
# are listed explicitly: "*" there would fail the RBAC escalation check.
locals {
  rw_verbs = ["get", "list", "watch", "create", "update", "patch", "delete", "deletecollection"]
}

resource "kubernetes_service_account_v1" "ws" {
  depends_on = [time_sleep.capsule_rbac]
  metadata {
    name      = "workspace"
    namespace = local.ns
  }
  automount_service_account_token = true
}

resource "kubernetes_role_v1" "ws" {
  depends_on = [time_sleep.capsule_rbac]
  metadata {
    name      = "workspace"
    namespace = local.ns
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims"]
    verbs      = local.rw_verbs
  }
  # pods/exec kept: exec into lab DB pods is the main
  # debugging tool, and pod create already reaches everything exec could.
  rule {
    api_groups = [""]
    resources  = ["pods/exec", "pods/portforward"]
    verbs      = ["get", "create"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/log", "events"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets"]
    verbs      = local.rw_verbs
  }
  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = local.rw_verbs
  }
  rule {
    api_groups = ["postgresql.cnpg.io"]
    resources  = ["clusters"]
    verbs      = ["*"]
  }
  rule {
    api_groups = ["minio.min.io"]
    resources  = ["tenants"]
    verbs      = ["*"]
  }
  rule {
    api_groups = ["moco.cybozu.com"]
    resources  = ["mysqlclusters"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding_v1" "ws" {
  metadata {
    name      = "workspace"
    namespace = local.ns
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.ws.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.ws.metadata[0].name
    namespace = local.ns
  }
}
