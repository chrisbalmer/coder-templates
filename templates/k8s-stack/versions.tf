terraform {
  # CI pins Terraform 1.15.5, the version Coder 2.37.3's provisioner ships.
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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
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
