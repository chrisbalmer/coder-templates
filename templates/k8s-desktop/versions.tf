terraform {
  # CI pins Terraform 1.16.2, the version Coder 2.38.0's provisioner ships.
  required_version = ">= 1.15"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.18"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}

provider "coder" {}

# In-cluster config: the provisioner's ServiceAccount, with the rights listed in
# REQUIREMENTS.md.
provider "kubernetes" {}
