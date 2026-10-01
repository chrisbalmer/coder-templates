# Ephemeral MinIO (MinIO Operator). The Tenant is created on start and removed
# on stop. Unlike CNPG and MOCO, the operator leaves the tenant's PVC behind,
# so the next start reuses it: root credentials are therefore created
# unconditionally and never change, or a reused volume would not open.

locals {
  lab_minio = data.coder_parameter.lab_minio.value == "true"
}

resource "random_password" "minio" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "lab_minio" {
  count      = local.lab_minio ? local.start : 0
  depends_on = [time_sleep.capsule_rbac]
  metadata {
    name      = "lab-minio"
    namespace = local.ns
  }
  data = {
    # Read by the operator (spec.configuration).
    "config.env" = <<-EOT
      export MINIO_ROOT_USER="lab"
      export MINIO_ROOT_PASSWORD="${random_password.minio.result}"
    EOT
    # Read by the labs script.
    user     = "lab"
    password = random_password.minio.result
  }
}

resource "kubernetes_manifest" "lab_minio" {
  count      = local.lab_minio ? local.start : 0
  depends_on = [kubernetes_secret_v1.lab_minio]

  manifest = {
    apiVersion = "minio.min.io/v2"
    kind       = "Tenant"
    metadata = {
      name      = "lab-minio"
      namespace = local.ns
    }
    spec = {
      # Set explicitly: the operator would default to Docker Hub. See the
      # lab_minio_image variable.
      image           = var.lab_minio_image
      configuration   = { name = "lab-minio" }
      requestAutoCert = false
      buckets         = [{ name = "test" }]
      pools = [{
        name             = "pool-0"
        servers          = 1
        volumesPerServer = 1
        volumeClaimTemplate = {
          metadata = { name = "data" }
          spec = {
            accessModes      = ["ReadWriteOnce"]
            storageClassName = local.storage_class
            resources        = { requests = { storage = "1Gi" } }
          }
        }
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "1", memory = "1Gi" }
        }
      }]
    }
  }
}
