# terraform test, from modules/herdr: checks what the module renders. The
# script itself is exercised by scripts/test-herdr-module.sh.

mock_provider "coder" {}

variables {
  agent_id = "agent"
}

run "defaults" {
  command = plan

  assert {
    condition     = strcontains(output.script, "HERDR_VERSION='0.9.3'")
    error_message = "default version is not passed to the script"
  }
  assert {
    condition     = strcontains(output.script, "linux-x86_64=18a8dc65f1c2fa485884344356dea1cfd911c6f06cf46fa78e193f4087f4dba7")
    error_message = "the built-in checksum table is not used"
  }
  assert {
    condition     = strcontains(output.script, "HERDR_INTEGRATIONS='claude'")
    error_message = "claude is not the default integration"
  }
  assert {
    condition     = output.app_command == "export PATH=\"$HOME/.local/bin:$PATH\"; exec \"$HOME/.local/bin/herdr\""
    error_message = "unexpected app command: ${output.app_command}"
  }
  assert {
    condition     = length(coder_app.herdr) == 1 && coder_app.herdr[0].slug == "herdr"
    error_message = "the app is missing"
  }
  assert {
    condition     = strcontains(output.script, "HERDR_START_SERVER='false'") && strcontains(output.script, "HERDR_WAIT_FOR=''")
    error_message = "server or ordering on by default"
  }
  assert {
    condition     = output.scripts == ["herdr-script"] && strcontains(output.script, "HERDR_SYNC_UNIT='herdr-script'")
    error_message = "sync unit isn't herdr-script"
  }
}

run "ordering_and_server" {
  command = plan

  variables {
    wait_for_scripts = ["coder-claude-code-pre_install_script", "coder-claude-code-install_script"]
    start_server     = true
    workdir          = "/home/coder/repo"
    slug             = "agents"
  }

  assert {
    condition     = strcontains(output.script, "HERDR_WAIT_FOR='coder-claude-code-pre_install_script coder-claude-code-install_script'")
    error_message = "wait_for_scripts not passed"
  }
  assert {
    condition     = strcontains(output.script, "HERDR_START_SERVER='true'") && strcontains(output.script, "HERDR_WORKDIR='/home/coder/repo'")
    error_message = "start_server or workdir not passed"
  }
  assert {
    condition     = output.scripts == ["agents-script"]
    error_message = "sync unit doesn't follow the slug"
  }
}

run "workdir_is_quoted" {
  command = plan

  variables {
    workdir = "/home/coder/it's here"
  }

  assert {
    condition     = strcontains(output.app_command, "cd '/home/coder/it'\\''s here' 2>/dev/null; ")
    error_message = "workdir is not single-quoted: ${output.app_command}"
  }
  assert {
    condition     = strcontains(output.script, "HERDR_WORKDIR='/home/coder/it'\\''s here'")
    error_message = "HERDR_WORKDIR is not single-quoted"
  }
}

run "preinstalled" {
  command = plan

  variables {
    install       = false
    herdr_version = "9.9.9"
    integrations  = []
    app           = false
  }

  assert {
    condition     = strcontains(output.script, "HERDR_INSTALL='false'") && strcontains(output.script, "HERDR_INTEGRATIONS=''")
    error_message = "install=false or empty integrations not passed"
  }
  assert {
    condition     = length(coder_app.herdr) == 0
    error_message = "app=false still creates the app"
  }
}

run "custom_checksums" {
  command = plan

  variables {
    herdr_version = "9.9.9"
    checksums     = { "linux-x86_64" = "0000000000000000000000000000000000000000000000000000000000000000" }
  }

  assert {
    condition     = strcontains(output.script, "HERDR_CHECKSUMS='linux-x86_64=0000000000000000000000000000000000000000000000000000000000000000'")
    error_message = "checksums input not used"
  }
}

run "unknown_version_needs_checksums" {
  command = plan

  variables {
    herdr_version = "9.9.9"
  }

  expect_failures = [coder_script.herdr]
}

run "bad_integration_name" {
  command = plan

  variables {
    integrations = ["claude; rm -rf ~"]
  }

  expect_failures = [var.integrations]
}

run "bad_wait_for_unit" {
  command = plan

  variables {
    wait_for_scripts = ["install; reboot"]
  }

  expect_failures = [var.wait_for_scripts]
}

run "bad_slug" {
  command = plan

  variables {
    slug = "Herdr App"
  }

  expect_failures = [var.slug]
}

run "relative_workdir" {
  command = plan

  variables {
    workdir = "project"
  }

  expect_failures = [var.workdir]
}
