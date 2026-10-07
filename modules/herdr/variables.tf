variable "agent_id" {
  type        = string
  description = "ID of the coder_agent the script and app run on."
}

variable "herdr_version" {
  type        = string
  description = "herdr release to install, without the leading v. Versions in the module's checksum table need no checksums input."
  default     = "0.9.3"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.herdr_version))
    error_message = "herdr_version must look like 0.9.3."
  }
}

variable "checksums" {
  type        = map(string)
  description = <<-EOF
  SHA-256 of each release binary for herdr_version, keyed by platform
  (linux-x86_64, linux-aarch64, macos-x86_64, macos-aarch64). Leave empty to
  use the module's table, which covers its default version. Only the
  workspace's own platform needs an entry.
  EOF
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.checksums) : contains(["linux-x86_64", "linux-aarch64", "macos-x86_64", "macos-aarch64"], k)])
    error_message = "checksums keys must be linux-x86_64, linux-aarch64, macos-x86_64 or macos-aarch64."
  }

  validation {
    condition     = alltrue([for v in values(var.checksums) : can(regex("^[0-9a-f]{64}$", v))])
    error_message = "Each checksum must be 64 lowercase hex characters."
  }
}

variable "install" {
  type        = bool
  description = "Install herdr into ~/.local/bin. false uses the herdr already on PATH, for an image that bakes it in."
  default     = true
}

variable "integrations" {
  type        = list(string)
  description = "herdr agent integrations to install on every start (herdr integration install <name>), so herdr can resume those agents' sessions after a restart."
  default     = ["claude"]

  validation {
    condition     = alltrue([for i in var.integrations : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", i))])
    error_message = "Integration names are lowercase letters, digits and dashes, as listed by herdr integration status."
  }
}

variable "wait_for_scripts" {
  type        = list(string)
  description = <<-EOF
  coder exp sync unit names to wait for before the script runs, such as the
  claude-code module's scripts output. The agents need to be installed before
  herdr's integrations and a started server can use them.
  EOF
  default     = []

  validation {
    condition     = alltrue([for u in var.wait_for_scripts : can(regex("^[A-Za-z0-9._-]+$", u))])
    error_message = "Unit names are letters, digits, '.', '_' and '-'."
  }
}

variable "start_server" {
  type        = bool
  description = "Start herdr's headless server on every workspace start, so the saved layout is restored, and agents resumed, before anyone opens herdr."
  default     = false
}

variable "install_skill" {
  type        = bool
  description = "Write herdr's agent skill (herdr --skill) to ~/.agents/skills/herdr and ~/.claude/skills/herdr."
  default     = true
}

variable "app" {
  type        = bool
  description = "Add a Herdr app that opens herdr in a terminal."
  default     = true
}

variable "workdir" {
  type        = string
  description = "Absolute path the app starts herdr in, when it exists. null starts it in the home directory."
  default     = null

  validation {
    condition     = var.workdir == null || startswith(coalesce(var.workdir, "/"), "/")
    error_message = "workdir must be an absolute path."
  }
}

variable "display_name" {
  type        = string
  description = "Name of the app, and of the script in the workspace's startup logs."
  default     = "Herdr"
}

variable "icon" {
  type        = string
  description = "Icon for the app and script. Use a path coderd serves (/icon/*, /emojis/*)."
  default     = "/emojis/1f411.png"
}

variable "slug" {
  type        = string
  description = "Slug of the app. Also names the script's coder exp sync unit, <slug>-script."
  default     = "herdr"

  validation {
    condition     = can(regex("^[a-z0-9](-?[a-z0-9])*$", var.slug))
    error_message = "slug must be lowercase letters and digits, with single dashes between them."
  }
}

variable "order" {
  type        = number
  description = "Position of the app among the workspace's apps."
  default     = null
}

variable "group" {
  type        = string
  description = "Name of an app group to put the app in."
  default     = null
}
