variable "image_registry" {
  type        = string
  description = <<-EOF
  Registry and owner the workspace images are pulled from, without a trailing
  slash. Images are <image_registry>/coder-images-<name>:<version>. Point it
  at a mirror that carries the same names and versions.
  EOF
  default     = "ghcr.io/chrisbalmer"

  validation {
    condition     = var.image_registry != "" && !endswith(var.image_registry, "/")
    error_message = "image_registry must be set and must not end with a slash."
  }
}

variable "storage_class" {
  type        = string
  description = <<-EOF
  StorageClass for the home volume, used for every workspace. Leave it empty to
  offer storage_class_options as a parameter, or, with no options either, to
  use the cluster's default StorageClass.
  EOF
  default     = ""
}

variable "storage_class_options" {
  type        = list(string)
  description = <<-EOF
  StorageClasses users may pick from when storage_class is empty. The first is
  the default. Empty: no parameter, and the cluster's default StorageClass.
  EOF
  default     = []
}

variable "default_dotfiles_uri" {
  type        = string
  description = <<-EOF
  Pre-filled value of the Dotfiles URL parameter. {username} is replaced with
  the workspace owner's Coder username. Users can change it per workspace.
  Empty: no dotfiles unless the user sets a URL.
  EOF
  default     = "git@github.com:{username}/dotfiles.git"
}

variable "ssh_known_hosts_extra" {
  type        = string
  description = <<-EOF
  Extra SSH host keys, in known_hosts format (one per line), added to the
  workspace's /etc/ssh/ssh_known_hosts after GitHub's. Use it for a self-hosted
  forge that workspaces clone from over SSH, e.g. "git.example.com ssh-ed25519 AAAA...".
  EOF
  default     = ""
}

variable "app_subdomain" {
  type        = bool
  description = <<-EOF
  Serve the desktop on its own subdomain. Needs a wildcard access URL on the
  Coder deployment (CODER_WILDCARD_ACCESS_URL). false serves it on a path
  instead, which KasmVNC supports less well.
  EOF
  default     = true
}
