# Presets are the selection surface for Coder Tasks/AI. Each description is
# intent + concrete signals + an explicit exclusion, so an agent can tell two
# neighbouring presets apart. General is the default,
# so a task that does not choose gets the cheapest workspace. Descriptions are
# capped at 128 characters by the provider, so the detail lives in the
# parameter and option descriptions in params.tf.
#
# Coder reads presets by type; nothing references them, hence tflint-ignore.

# tflint-ignore: terraform_unused_declarations
data "coder_workspace_preset" "general" {
  name        = "General"
  default     = true
  description = "No toolchain, no labs. For shell, git, Python or kubectl tasks, or when unsure. Not for Go, Node or Cortex builds."
  icon        = "/icon/terminal.svg"
  parameters = {
    image        = "base"
    cpu          = "2"
    memory       = "4"
    lab_postgres = "false"
    lab_minio    = "false"
    lab_mysql    = "false"
    herdr        = "true"
    herdr_server = "false"
  }
}

# tflint-ignore: terraform_unused_declarations
data "coder_workspace_preset" "cortex" {
  name        = "Cortex content"
  description = "Cortex XSOAR/XSIAM content: integrations, scripts, playbooks, packs (demisto-sdk). Not for Kubernetes, infra or Go."
  icon        = "/icon/python.svg"
  parameters = {
    image        = "cortex"
    cpu          = "2"
    memory       = "4"
    lab_postgres = "false"
    lab_minio    = "false"
    lab_mysql    = "false"
    herdr        = "true"
    herdr_server = "false"
  }
}

# tflint-ignore: terraform_unused_declarations
data "coder_workspace_preset" "infra" {
  name        = "Infrastructure"
  description = "Kubernetes, Flux, Helm, Kustomize, Terraform, Talos, Ansible: cluster config and IaC. Not for application code."
  icon        = "/icon/k8s.png"
  parameters = {
    image        = "infra"
    cpu          = "2"
    memory       = "4"
    lab_postgres = "false"
    lab_minio    = "false"
    lab_mysql    = "false"
    herdr        = "true"
    herdr_server = "false"
  }
}

# tflint-ignore: terraform_unused_declarations
data "coder_workspace_preset" "go" {
  name        = "Go service"
  description = "Go-only backend or CLI, with a throwaway Postgres for tests. If there is a web frontend, use App (Go + React)."
  icon        = "/icon/go.svg"
  parameters = {
    image        = "golang"
    cpu          = "4"
    memory       = "8"
    lab_postgres = "true"
    lab_minio    = "false"
    lab_mysql    = "false"
    herdr        = "true"
    herdr_server = "false"
  }
}

# tflint-ignore: terraform_unused_declarations
data "coder_workspace_preset" "app" {
  name        = "App (Go + React)"
  description = "Go backend + React/TypeScript frontend (+ Helm), with throwaway Postgres and S3 for tests. Not for Go-only services."
  icon        = "/icon/typescript.svg"
  parameters = {
    image        = "app"
    cpu          = "4"
    memory       = "8"
    lab_postgres = "true"
    lab_minio    = "true"
    lab_mysql    = "false"
    herdr        = "true"
    herdr_server = "false"
  }
}
