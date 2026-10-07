# Parameter and option descriptions are read by Coder AI as well as humans:
# they are a routing table. Keep them in step with
# presets.tf, and treat wording changes as releases.

data "coder_parameter" "image" {
  name         = "image"
  display_name = "Toolchain image"
  description  = "Which toolchain the workspace container has. Every image includes git, Python, uv, kubectl, sudo, the lab clients (psql, mysql, mc) and the gh, tea and fj CLIs; each option adds to that."
  type         = "string"
  default      = "base"
  mutable      = false
  icon         = "/icon/docker.png"
  order        = 1

  option {
    name        = "General"
    value       = "base"
    description = "No language toolchain. Use when the task only needs a shell, git, Python and kubectl, or is unclear."
  }
  option {
    name        = "Cortex content"
    value       = "cortex"
    description = "Palo Alto Cortex XSOAR/XSIAM content development with demisto-sdk. Not for Kubernetes or Go work."
  }
  option {
    name        = "Infrastructure"
    value       = "infra"
    description = "Kubernetes, Flux, Helm, Kustomize, Terraform, Talos, Cilium and Ansible. For cluster config and IaC, not application code."
  }
  option {
    name        = "Go"
    value       = "golang"
    description = "Go backend or CLI work: Go, golangci-lint, gopls, dlv, goreleaser, air. No Node.js."
  }
  option {
    name        = "App (Go + React)"
    value       = "app"
    description = "Full-stack Go backend plus React/TypeScript frontend: everything in Go, plus Node.js LTS, pnpm and Helm."
  }
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "CPU cores (limit). The largest option plus all three labs fits the namespace quota."
  type         = "number"
  default      = "2"
  mutable      = true
  icon         = "/icon/memory.svg"
  order        = 2

  dynamic "option" {
    for_each = [2, 4, 6, 8]
    content {
      name  = "${option.value} cores"
      value = tostring(option.value)
    }
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  description  = "Memory in GiB (limit)."
  type         = "number"
  default      = "4"
  mutable      = true
  icon         = "/icon/memory.svg"
  order        = 3

  dynamic "option" {
    for_each = [4, 8, 12, 16]
    content {
      name  = "${option.value} GiB"
      value = tostring(option.value)
    }
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Home disk size"
  description  = "Size of the persistent /home/coder volume in GiB. Fixed at creation."
  type         = "number"
  default      = "10"
  mutable      = false
  icon         = "/emojis/1f4be.png"
  order        = 4

  validation {
    min = 1
    max = 100
  }
}

data "coder_parameter" "repo" {
  name         = "repo"
  display_name = "Git repository"
  description  = "Repository to clone into the home directory on start (HTTPS or SSH URL). Leave empty for none."
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "/icon/git.svg"
  order        = 5
}

data "coder_parameter" "herdr" {
  name         = "herdr"
  display_name = "herdr"
  description  = "Installs herdr, a terminal multiplexer for coding agents, with a Herdr app. Its panes come back after a stop, and Claude Code resumes its conversations."
  type         = "bool"
  default      = "true"
  mutable      = true
  icon         = "/emojis/1f411.png"
  order        = 6
}

data "coder_parameter" "herdr_server" {
  name         = "herdr_server"
  display_name = "herdr: start on boot"
  description  = "Starts herdr's server on every workspace start, so your panes and Claude Code sessions are back before you open herdr. Needs herdr on."
  type         = "bool"
  default      = "false"
  mutable      = true
  icon         = "/emojis/1f411.png"
  order        = 7
}

data "coder_parameter" "lab_postgres" {
  name         = "lab_postgres"
  display_name = "Lab: PostgreSQL"
  description  = "Creates a throwaway PostgreSQL 18 (CloudNativePG) in this workspace's namespace on every start. Exposes DATABASE_URL and PG* variables. Data is dropped on stop."
  type         = "bool"
  default      = "false"
  mutable      = true
  icon         = "/icon/postgres.svg"
  order        = 10
}

data "coder_parameter" "lab_minio" {
  name         = "lab_minio"
  display_name = "Lab: MinIO (S3)"
  description  = "Creates a throwaway S3-compatible MinIO with a bucket named test on every start. Exposes AWS_ENDPOINT_URL_S3, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and a MinIO client alias named lab. For tests, not for keeping data."
  type         = "bool"
  default      = "false"
  mutable      = true
  icon         = "/emojis/1faa3.png"
  order        = 11
}

data "coder_parameter" "lab_mysql" {
  name         = "lab_mysql"
  display_name = "Lab: MySQL"
  description  = "Creates a throwaway MySQL 8.4 (MOCO) with a database named app on every start. Exposes MYSQL_URL. Data is dropped on stop. Only enable if the project uses MySQL."
  type         = "bool"
  default      = "false"
  mutable      = true
  icon         = "/emojis/1f42c.png"
  order        = 12
}

data "coder_parameter" "storage_class" {
  # Only when the admin offers a choice: storage_class unset and
  # storage_class_options listed.
  count        = var.storage_class == "" && length(var.storage_class_options) > 0 ? 1 : 0
  name         = "storage_class"
  display_name = "Storage class"
  description  = "StorageClass for the home directory and lab volumes. Can't be changed after the workspace is created."
  type         = "string"
  default      = var.storage_class_options[0]
  mutable      = false
  icon         = "/emojis/1f4be.png"
  order        = 20

  dynamic "option" {
    for_each = var.storage_class_options
    content {
      name  = option.value
      value = option.value
    }
  }
}
