# Unguarded: survives stop. Never modified after creation; workspace delete
# removes it with the namespace (reclaimPolicy Delete).
resource "kubernetes_persistent_volume_claim_v1" "home" {
  depends_on = [time_sleep.capsule_rbac]
  metadata {
    name      = "home"
    namespace = local.ns
    labels    = local.labels
  }
  wait_until_bound = false
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = local.storage_class
    resources {
      requests = {
        storage = "${data.coder_parameter.home_disk_size.value}Gi"
      }
    }
  }

  lifecycle {
    ignore_changes = all
  }
}

# Keeps the agent token out of the Deployment manifest (and its plan output).
resource "kubernetes_secret_v1" "agent_token" {
  count      = local.start
  depends_on = [time_sleep.capsule_rbac]
  metadata {
    name      = "coder-agent-token"
    namespace = local.ns
  }
  data = {
    token = coder_agent.main.token
  }
}

resource "kubernetes_config_map_v1" "ssh_known_hosts" {
  depends_on = [time_sleep.capsule_rbac]
  metadata {
    name      = "ssh-known-hosts"
    namespace = local.ns
  }
  data = {
    # GitHub's published keys, then any the admin adds.
    "ssh_known_hosts" = join("", [
      <<-EOT
      github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
      github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
      github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
      EOT
      ,
      var.ssh_known_hosts_extra == "" ? "" : "${trimspace(var.ssh_known_hosts_extra)}\n",
    ])
  }
}

locals {
  # NET_RAW is dropped unless the user asks for it (nmap SYN scans, tcpdump,
  # ping). With hostUsers: false it only reaches the pod's own network
  # namespace, and baseline Pod Security allows it either way.
  drop_caps = data.coder_parameter.net_raw.value ? ["MKNOD"] : ["NET_RAW", "MKNOD"]
}

# kubernetes_manifest rather than kubernetes_deployment_v1: the provider
# (3.2.1) has no host_users field, and user namespaces are required.
resource "kubernetes_manifest" "workspace" {
  count = local.start
  depends_on = [
    kubernetes_persistent_volume_claim_v1.home,
    kubernetes_secret_v1.agent_token,
    kubernetes_config_map_v1.ssh_known_hosts,
  ]

  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "workspace"
      namespace = local.ns
      labels    = local.labels
    }
    spec = {
      replicas = 1
      strategy = { type = "Recreate" }
      selector = {
        matchLabels = { "app.kubernetes.io/name" = "coder-workspace" }
      }
      template = {
        metadata = {
          labels = merge(local.labels, { "app.kubernetes.io/name" = "coder-workspace" })
        }
        spec = {
          # No Kubernetes API access: a desktop has no lab resources to manage,
          # and a security lab shouldn't hold cluster credentials.
          automountServiceAccountToken = false
          enableServiceLinks           = false
          # User namespaces: container root maps to an unprivileged host uid.
          hostUsers    = false
          nodeSelector = { "kubernetes.io/arch" = "amd64" }
          securityContext = {
            runAsUser  = 1000
            runAsGroup = 1000
            fsGroup    = 1000
            # Lets every group open ICMP echo (datagram) sockets, so ping works
            # without NET_RAW: Kali's iputils has no file capability, and the
            # pod default only allows group 65534. A Kubernetes "safe" sysctl,
            # scoped to the pod's own network namespace.
            sysctls = [{ name = "net.ipv4.ping_group_range", value = "0 2147483647" }]
          }
          containers = [{
            name            = "dev"
            image           = local.images[data.coder_parameter.image.value]
            imagePullPolicy = "IfNotPresent"
            command         = ["sh", "-c", coder_agent.main.init_script]
            env = [{
              name = "CODER_AGENT_TOKEN"
              valueFrom = {
                secretKeyRef = { name = "coder-agent-token", key = "token" }
              }
            }]
            resources = {
              requests = { cpu = "500m", memory = "1Gi" }
              limits = {
                cpu    = data.coder_parameter.cpu.value
                memory = "${data.coder_parameter.memory.value}Gi"
              }
            }
            # PSA baseline, not restricted: the images keep NOPASSWD sudo, so
            # never set allowPrivilegeEscalation=false or drop SETUID/SETGID.
            securityContext = {
              seccompProfile = { type = "RuntimeDefault" }
              capabilities   = { drop = local.drop_caps }
            }
            volumeMounts = [
              { name = "home", mountPath = local.home_path },
              { name = "dshm", mountPath = "/dev/shm" },
              { name = "ssh-known-hosts", mountPath = "/etc/ssh/ssh_known_hosts", subPath = "ssh_known_hosts", readOnly = true },
            ]
          }]
          volumes = [
            { name = "home", persistentVolumeClaim = { claimName = kubernetes_persistent_volume_claim_v1.home.metadata[0].name } },
            # The runtime's default /dev/shm is 64 MiB; browsers and the X
            # server need more. Counts against the memory limit.
            { name = "dshm", emptyDir = { medium = "Memory", sizeLimit = "1Gi" } },
            { name = "ssh-known-hosts", configMap = { name = kubernetes_config_map_v1.ssh_known_hosts.metadata[0].name } },
          ]
          affinity = {
            podAntiAffinity = {
              preferredDuringSchedulingIgnoredDuringExecution = [{
                weight = 1
                podAffinityTerm = {
                  topologyKey = "kubernetes.io/hostname"
                  # Spread across every workspace, not just this namespace.
                  namespaceSelector = {
                    matchLabels = { "coder.io/tenant" = "true" }
                  }
                  labelSelector = {
                    matchLabels = { "app.kubernetes.io/name" = "coder-workspace" }
                  }
                }
              }]
            }
          }
        }
      }
    }
  }
}
