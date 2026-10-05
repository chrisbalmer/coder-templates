variable "agent_id" {
  type        = string
  description = "ID of the coder_agent the script runs on."
}

variable "sources" {
  type = list(object({
    name          = string
    url           = string
    ref           = string
    skills        = optional(list(string), ["*"])
    claude_plugin = optional(bool, true)
  }))
  description = <<-EOF
  Git repositories to install skills from, in priority order: when two sources
  provide a skill with the same name, the earlier one wins.
  - name: short id, used for the checkout directory and in logs.
  - url: HTTPS or SSH (scp-form or ssh://) clone URL.
  - ref: tag or branch to check out.
  - skills: skill names (directory names) to install; "*" anywhere in the
    list installs all.
  - claude_plugin: register the repo's .claude-plugin/marketplace.json with
    Claude Code (managed settings) instead of copying its skills to
    ~/.claude/skills.
  EOF
  default     = []

  validation {
    condition     = alltrue([for s in var.sources : can(regex("^[a-z0-9][a-z0-9._-]*$", s.name))])
    error_message = "Each source name must be lowercase letters, digits, '.', '_' or '-', starting with a letter or digit."
  }

  validation {
    condition     = length(distinct([for s in var.sources : s.name])) == length(var.sources)
    error_message = "Source names must be unique."
  }

  validation {
    condition     = alltrue([for s in var.sources : trimspace(s.url) != "" && trimspace(s.ref) != ""])
    error_message = "Each source needs a url and a ref."
  }

  validation {
    # git would read them as options.
    condition     = alltrue([for s in var.sources : !startswith(s.url, "-") && !startswith(s.ref, "-")])
    error_message = "A source's url and ref must not start with \"-\"."
  }

  validation {
    condition     = alltrue([for s in var.sources : length(s.skills) > 0])
    error_message = "skills must list at least one name, or [\"*\"] for all."
  }
}

variable "display_name" {
  type        = string
  description = "Name of the script in the workspace's startup logs."
  default     = "Agent skills"
}

variable "icon" {
  type        = string
  description = "Icon for the script. Use a path coderd serves (/icon/*, /emojis/*)."
  default     = "/emojis/1f9f0.png"
}

variable "claude_managed_settings_dir" {
  type        = string
  description = <<-EOF
  Claude Code's managed-settings drop-in directory. The script writes
  30-agent-skills.json here, with sudo when the directory isn't writable by the
  workspace user. Override it only for testing.
  EOF
  default     = "/etc/claude-code/managed-settings.d"

  validation {
    condition     = startswith(var.claude_managed_settings_dir, "/")
    error_message = "claude_managed_settings_dir must be an absolute path."
  }
}
