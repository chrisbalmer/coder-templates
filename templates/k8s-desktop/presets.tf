# Presets are the selection surface for Coder Tasks/AI. Each description is
# intent + concrete signals + an explicit exclusion, so an agent can tell the
# two apart. Ubuntu is the default. Descriptions are capped at 128 characters
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
    cpu     = "4"
    memory  = "8"
    net_raw = "false"
  }
}

# tflint-ignore: terraform_unused_declarations
data "coder_workspace_preset" "kali" {
  name        = "Kali security lab"
  description = "Kali desktop for security labs, CTFs and static malware analysis, with raw sockets. Not for general development."
  icon        = "/emojis/1f409.png"
  parameters = {
    image   = "kali-desktop"
    cpu     = "4"
    memory  = "8"
    net_raw = "true"
  }
}
