locals {
  # Passed to the script as base64 JSON, so no value is ever parsed by the shell
  # or by Terraform's template syntax.
  config = {
    managed_settings_dir = var.claude_managed_settings_dir
    sources              = var.sources
  }

  # run.sh is a plain bash script (checked by shellcheck as is); the wrapper
  # hands it the config in the environment.
  script = <<-EOT
    #!/usr/bin/env bash
    AGENT_SKILLS_CONFIG='${base64encode(jsonencode(local.config))}' \
      exec bash -c "$(printf '%s' '${base64encode(file("${path.module}/scripts/run.sh"))}' | base64 -d)" agent-skills
  EOT
}

resource "coder_script" "agent_skills" {
  agent_id           = var.agent_id
  display_name       = var.display_name
  icon               = var.icon
  run_on_start       = true
  start_blocks_login = false
  script             = local.script
}
