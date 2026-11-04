# Presets are the selection surface for Coder Tasks/AI. Each description is
# intent + concrete signals + an explicit exclusion, so an agent can tell
# them apart. Ubuntu is the default. Descriptions are capped at 128 characters
# by the provider, so the detail lives in params.tf.
#
# Coder reads presets by type; nothing references them, hence tflint-ignore.

# tflint-ignore: terraform_unused_declarations
data "coder_workspace_preset" "ubuntu" {
  name        = "Ubuntu desktop"
  default     = true
  description = "General GUI work in a browser desktop: GUI apps, browsers, visual tools. Not for security labs or CTFs."
  icon        = "/icon/ubuntu.svg"
  parameters = {
    image   = "ubuntu-desktop"
    desktop = "true"
    cpu     = "4"
    memory  = "8"
    net_raw = "false"
  }
}

# tflint-ignore: terraform_unused_declarations
data "coder_workspace_preset" "kali" {
  name        = "Kali security lab"
  description = "Kali desktop for security labs, reverse engineering and static malware analysis, with raw sockets. Not for general development."
  icon        = "/emojis/1f409.png"
  parameters = {
    image   = "kali-desktop"
    desktop = "true"
    cpu     = "4"
    memory  = "8"
    net_raw = "true"
  }
}

# tflint-ignore: terraform_unused_declarations
data "coder_workspace_preset" "kali_headless" {
  name        = "Kali headless"
  description = "Kali with no desktop, over SSH: reverse engineering with Ghidra MCP, gdb and angr from a terminal or agent. No GUI."
  icon        = "/icon/terminal.svg"
  parameters = {
    image   = "kali-desktop"
    desktop = "false"
    cpu     = "4"
    memory  = "8"
    net_raw = "true"
  }
}
