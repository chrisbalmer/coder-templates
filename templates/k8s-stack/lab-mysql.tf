# Ephemeral MySQL (MOCO). The CR is created on start and removed on stop; MOCO
# deletes its PVCs with the cluster. MOCO generates the user passwords itself
# (secret moco-lab-mysql), so the labs script reads them at start.

locals {
  lab_mysql = data.coder_parameter.lab_mysql.value == "true"
}

# MOCO defaults innodb_log_file_size to 800M, which MySQL 8.4 turns into about
# 1.6 GB of redo log, created 50 MB at a time. On the 1Gi lab volume that
# fills the disk and mysqld crash-loops with "No space left on device"
# 50M gives MySQL's own default of about 100 MB of redo.
resource "kubernetes_config_map_v1" "lab_mysql" {
  count      = local.lab_mysql ? local.start : 0
  depends_on = [time_sleep.capsule_rbac]

  metadata {
    name      = "lab-mysql-config"
    namespace = local.ns
  }
  data = {
    innodb_log_file_size = "50M"
  }
}

resource "kubernetes_manifest" "lab_mysql" {
  count      = local.lab_mysql ? local.start : 0
  depends_on = [time_sleep.capsule_rbac, kubernetes_config_map_v1.lab_mysql]

  manifest = {
    apiVersion = "moco.cybozu.com/v1beta2"
    kind       = "MySQLCluster"
    metadata = {
      name      = "lab-mysql"
      namespace = local.ns
    }
    spec = {
      replicas           = 1
      mysqlConfigMapName = "lab-mysql-config"
      # One fewer container against the quota; nothing reads slow logs here.
      disableSlowQueryLogContainer = true
      podTemplate = {
        spec = {
          containers = [{
            name  = "mysqld"
            image = "ghcr.io/cybozu-go/moco/mysql:8.4.10"
            resources = {
              requests = { cpu = "100m", memory = "512Mi" }
              limits   = { cpu = "1", memory = "1Gi" }
            }
          }]
        }
      }
      volumeClaimTemplates = [{
        metadata = { name = "mysql-data" }
        spec = {
          accessModes      = ["ReadWriteOnce"]
          storageClassName = local.storage_class
          resources        = { requests = { storage = "1Gi" } }
        }
      }]
    }
  }
}
