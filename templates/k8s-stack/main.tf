data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

locals {
  # Exact pins, bumped by template release. Built by coder-images
  # (github.com/chrisbalmer/coder-images).
  images = {
    base   = "${var.image_registry}/coder-images-base:2.3.0"
    cortex = "${var.image_registry}/coder-images-cortex:2.3.0"
    infra  = "${var.image_registry}/coder-images-infra:2.3.0"
    golang = "${var.image_registry}/coder-images-golang:2.4.0"
    app    = "${var.image_registry}/coder-images-app:2.3.0"
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
  # No dir: it's deprecated, and anything but $HOME breaks Coder Desktop file
  # sync. The modules below open the repo folder themselves, so the repo's
  # .mcp.json is listed by absolute path rather than relative to dir.
  env = {
    "CODER_AGENT_EXP_MCP_CONFIG_FILES" = "~/.coder/.mcp.json,${local.workspace_path}/.mcp.json"
  }

  # The home PVC hides anything the image put under /home/coder, so nothing
  # here may assume a seeded home. Shell config comes from dotfiles or /etc.
  startup_script = <<-EOT
    set -e
    # fsGroup leaves the PVC root owned by root; give it to the user.
    sudo chown coder:coder ${local.home_path}
    mkdir -p ${local.workspace_path} ~/.config/lab
    install -d -m 700 ~/.ssh

    # Lab connection strings live in ~/.config/lab/env (written by the labs
    # script); make every login shell load them.
    printf '%s\n' '[ -f "$HOME/.config/lab/env" ] && { set -a; . "$HOME/.config/lab/env"; set +a; }' \
      | sudo tee /etc/profile.d/coder-lab-env.sh >/dev/null
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

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # load average scaled by number of cores
    script   = <<-EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }
}

# Git identity comes from the user's own git config (dotfiles), so it's the same on every
# machine. The registry git-config module set GIT_AUTHOR_*/GIT_COMMITTER_* env vars, which
# override every config file, so dotfiles could never win. Instead this writes a fallback
# identity to the system config (/etc/gitconfig), the lowest-precedence level: anything in
# ~/.config/git/config, ~/.gitconfig or a repo's .git/config overrides it. It lives on the
# container filesystem, so it's rebuilt on every start and never touches the home volume.
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
    # Single-quoted for the shell, so a name or email is never expanded or HTML-escaped.
    sudo git config --system user.name '${replace(coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name), "'", "'\\''")}'
    sudo git config --system user.email '${replace(data.coder_workspace_owner.me.email, "'", "'\\''")}'
    echo "fallback identity: $(git config --system user.name) <$(git config --system user.email)>"
    echo "effective identity: $(git config user.name) <$(git config user.email)> (from $(git config --show-origin user.email | cut -f1))"
  EOT
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

module "claude-code" {
  count    = local.start
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.5.1"
  agent_id = coder_agent.main.id
  workdir  = local.workspace_path
}

module "vscode-web" {
  count          = local.start
  source         = "registry.coder.com/coder/vscode-web/coder"
  version        = "1.6.2"
  agent_id       = coder_agent.main.id
  accept_license = true
  folder         = local.workspace_path
}
