# Ephemeral PostgreSQL (CloudNativePG). The CR is created on start and removed
# on stop; CNPG owns its PVC, so the data goes with it. The password is
# unguarded so it stays stable across stops.

locals {
  lab_pg = data.coder_parameter.lab_postgres.value == "true"
}

resource "random_password" "pg" {
  count   = local.lab_pg ? 1 : 0
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "lab_pg_app" {
  count      = local.lab_pg ? local.start : 0
  depends_on = [time_sleep.capsule_rbac]
  metadata {
    name      = "lab-pg-app"
    namespace = local.ns
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "app"
    password = random_password.pg[0].result
  }
}

resource "kubernetes_manifest" "lab_pg" {
  count      = local.lab_pg ? local.start : 0
  depends_on = [kubernetes_secret_v1.lab_pg_app]

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata = {
      name      = "lab-pg"
      namespace = local.ns
    }
    spec = {
      instances = 1
      imageName = "ghcr.io/cloudnative-pg/postgresql:18.4"
      # A single-instance primary PDB would block node drains.
      enablePDB = false
      storage = {
        size         = "1Gi"
        storageClass = local.storage_class
      }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "1", memory = "1Gi" }
      }
      bootstrap = {
        initdb = {
          database = "app"
          owner    = "app"
          secret   = { name = "lab-pg-app" }
        }
      }
    }
  }
}
