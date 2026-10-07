locals {
  # SHA-256 of each release binary, from the release's asset digests. Bump
  # with scripts/herdr-checksums.sh <version>.
  builtin_checksums = {
    "0.9.3" = {
      "linux-x86_64"  = "18a8dc65f1c2fa485884344356dea1cfd911c6f06cf46fa78e193f4087f4dba7"
      "linux-aarch64" = "4de7aa3e25678812e92960de64f7c2aaa1bca1f0f80a3c5e559837e231e1f5c0"
      "macos-x86_64"  = "db62d548ff3e832b087a96b1894a08d26be3905f1830309cd556783f215d4054"
      "macos-aarch64" = "5173a3e0ae42d5d1ab7ebfa5d5e6329f7c3d23f8e1a3677c7ce3231da2884157"
    }
  }
  checksums = length(var.checksums) > 0 ? var.checksums : lookup(local.builtin_checksums, var.herdr_version, {})

  # This script's coder exp sync unit, so other scripts can wait for it.
  sync_unit = "${var.slug}-script"

  # Every value below but HERDR_WORKDIR is validated to a shell-safe
  # character set, so plain single quotes are enough; HERDR_WORKDIR has its
  # single quotes escaped. run.sh is a plain bash script (checked by
  # shellcheck as is); the wrapper hands it the settings in the environment.
  script = <<-EOT
    #!/usr/bin/env bash
    HERDR_VERSION='${var.herdr_version}' \
    HERDR_CHECKSUMS='${join(" ", [for k, v in local.checksums : "${k}=${v}"])}' \
    HERDR_INSTALL='${var.install}' \
    HERDR_INTEGRATIONS='${join(" ", var.integrations)}' \
    HERDR_SKILL='${var.install_skill}' \
    HERDR_SYNC_UNIT='${local.sync_unit}' \
    HERDR_WAIT_FOR='${join(" ", var.wait_for_scripts)}' \
    HERDR_START_SERVER='${var.start_server}' \
    HERDR_WORKDIR='${var.workdir != null ? replace(coalesce(var.workdir, "/"), "'", "'\\''") : ""}' \
      exec bash -c "$(printf '%s' '${base64encode(file("${path.module}/scripts/run.sh"))}' | base64 -d)" herdr
  EOT

  # ~/.local/bin goes first on PATH so herdr's panes, and agents in them, find
  # the herdr CLI even when no shell profile adds it.
  app_command = join("; ", compact([
    "export PATH=\"$HOME/.local/bin:$PATH\"",
    var.workdir != null ? "cd '${replace(coalesce(var.workdir, "/"), "'", "'\\''")}' 2>/dev/null" : "",
    var.install ? "exec \"$HOME/.local/bin/herdr\"" : "exec herdr",
  ]))
}

resource "coder_script" "herdr" {
  agent_id           = var.agent_id
  display_name       = var.display_name
  icon               = var.icon
  run_on_start       = true
  start_blocks_login = false
  script             = local.script

  lifecycle {
    precondition {
      condition     = !var.install || length(local.checksums) > 0
      error_message = "No checksums for herdr ${var.herdr_version}: pass checksums, or use a version in the module's table."
    }
  }
}

resource "coder_app" "herdr" {
  count        = var.app ? 1 : 0
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = var.display_name
  icon         = var.icon
  command      = local.app_command
  order        = var.order
  group        = var.group
}
