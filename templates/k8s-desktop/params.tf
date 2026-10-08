# Parameter and option descriptions are read by Coder AI as well as humans:
# they are a routing table. Keep them in step with
# presets.tf, and treat wording changes as releases.

data "coder_parameter" "image" {
  name         = "image"
  display_name = "Desktop"
  description  = "Which Linux desktop the workspace runs. Both use Xfce, served in the browser by KasmVNC, with passwordless sudo."
  type         = "string"
  default      = "ubuntu-desktop"
  mutable      = false
  icon         = "/icon/desktop.svg"
  order        = 1

  option {
    name        = "Ubuntu"
    value       = "ubuntu-desktop"
    description = "General GUI work on Ubuntu, with the same CLI tools as the headless images (git, Python, uv, kubectl, gh). Not for security tooling."
    icon        = "/icon/ubuntu.svg"
  }
  option {
    name        = "Kali Linux"
    value       = "kali-desktop"
    description = "Security labs, CTFs and static malware analysis with Kali's tools. Not for general development."
    icon        = "/emojis/1f409.png"
  }
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "CPU cores (limit)."
  type         = "number"
  default      = "4"
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
  description  = "Memory in GiB (limit). Includes the desktop's 1 GiB shared-memory area, so a browser has room to run."
  type         = "number"
  default      = "8"
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
  description  = "Size of the persistent /home/coder volume in GiB. Fixed at creation. Everything outside /home/coder is reset on every restart."
  type         = "number"
  default      = "20"
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

data "coder_parameter" "net_raw" {
  name         = "net_raw"
  display_name = "Raw sockets"
  description  = "Keep the NET_RAW capability, for nmap SYN scans, tcpdump, scapy and ping inside the workspace. Off by default."
  type         = "bool"
  default      = "false"
  mutable      = true
  icon         = "/emojis/1f50e.png"
  order        = 6
}

data "coder_parameter" "coder_login" {
  name         = "coder_login"
  display_name = "Log in the coder CLI"
  description  = "Puts a Coder session token for your account in the workspace (CODER_SESSION_TOKEN), so the coder CLI inside it is logged in as you. Any process in the workspace, AI agents included, can read the token. Off: run coder login when you need it."
  type         = "bool"
  default      = "false"
  mutable      = true
  icon         = "/icon/coder.svg"
  order        = 7
}

data "coder_parameter" "storage_class" {
  # Only when the admin offers a choice: storage_class unset and
  # storage_class_options listed.
  count        = var.storage_class == "" && length(var.storage_class_options) > 0 ? 1 : 0
  name         = "storage_class"
  display_name = "Storage class"
  description  = "StorageClass for the home directory. Can't be changed after the workspace is created."
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
