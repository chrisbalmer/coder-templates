data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

locals {
  # Exact pins, bumped by template release. Built by coder-images
  # (github.com/chrisbalmer/coder-images).
  images = {
    ubuntu-desktop = "${var.image_registry}/coder-images-ubuntu-desktop:2.3.0"
    kali-desktop   = "${var.image_registry}/coder-images-kali-desktop:2.2.0"
  }

  start = data.coder_workspace.me.start_count

  home_path      = "/home/coder"
  repo           = data.coder_parameter.repo.value
  repo_parts     = split("/", trimsuffix(local.repo, "/"))
  repo_folder    = local.repo != "" ? trimsuffix(element(local.repo_parts, length(local.repo_parts) - 1), ".git") : "workspace"
  workspace_path = "${local.home_path}/${local.repo_folder}"

  # null leaves storageClassName unset, so the cluster's default class applies.
  storage_class = (
    var.storage_class != "" ? var.storage_class :
    length(var.storage_class_options) > 0 ? data.coder_parameter.storage_class[0].value :
    null
  )

  labels = {
    "app.kubernetes.io/part-of" = "coder"
    "com.coder.resource"        = "true"
    "com.coder.workspace.id"    = data.coder_workspace.me.id
    "com.coder.workspace.name"  = data.coder_workspace.me.name
    "com.coder.user.id"         = data.coder_workspace_owner.me.id
    "com.coder.user.username"   = data.coder_workspace_owner.me.name
  }
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"

  # The home PVC hides anything the image put under /home/coder, so nothing
  # here may assume a seeded home. Shell config comes from dotfiles or /etc.
  startup_script = <<-EOT
    set -e
    # fsGroup leaves the PVC root owned by root; give it to the user.
    sudo chown coder:coder ${local.home_path}
    mkdir -p ${local.workspace_path}
    install -d -m 700 ~/.ssh
  EOT

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path ${local.home_path}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }
}

# Same fallback as k8s-stack: the system git config (/etc/gitconfig) is the
# lowest-precedence level, so the user's dotfiles always win. It lives on the
# container filesystem and is rebuilt on every start.
resource "coder_script" "git_identity" {
  count              = local.start
  agent_id           = coder_agent.main.id
  display_name       = "Git identity fallback"
  icon               = "/icon/git.svg"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    #!/usr/bin/env bash
    set -eu
    command -v git >/dev/null || { echo "git not installed; skipping"; exit 0; }
    # Single-quoted for the shell, so a name or email is never expanded or HTML-escaped.
    sudo git config --system user.name '${replace(coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name), "'", "'\\''")}'
    sudo git config --system user.email '${replace(data.coder_workspace_owner.me.email, "'", "'\\''")}'
    echo "fallback identity: $(git config --system user.name) <$(git config --system user.email)>"
  EOT
}

# The desktop. The images ship Xfce and KasmVNC; the module configures
# KasmVNC on localhost and starts it, and Coder proxies it, so there is no VNC
# password: access is the Coder session. kasm_version only matters for an
# image without KasmVNC, which the module would install it into.
module "kasmvnc" {
  count               = local.start
  source              = "registry.coder.com/coder/kasmvnc/coder"
  version             = "1.3.0"
  agent_id            = coder_agent.main.id
  desktop_environment = "xfce"
  kasm_version        = "1.5.0"
  subdomain           = var.app_subdomain
  order               = 1
}

module "git-clone" {
  count    = local.repo != "" ? local.start : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "2.0.5"
  agent_id = coder_agent.main.id
  url      = local.repo
  base_dir = local.home_path
}

module "dotfiles" {
  count                = local.start
  source               = "registry.coder.com/coder/dotfiles/coder"
  version              = "1.4.2"
  agent_id             = coder_agent.main.id
  default_dotfiles_uri = replace(var.default_dotfiles_uri, "{username}", data.coder_workspace_owner.me.name)
}

module "coder-login" {
  count    = local.start
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.1.1"
  agent_id = coder_agent.main.id
}
