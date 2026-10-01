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
  StorageClass for the home volume and the lab volumes, used for every
  workspace. Leave it empty to offer storage_class_options as a parameter, or,
  with no options either, to use the cluster's default StorageClass.
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
