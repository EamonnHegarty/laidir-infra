terraform {
  # 1.11+ is required for S3-native state locking (use_lockfile).
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Guard rail: refuse to run against any account other than the workload account.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project    = "laidir"
      Component  = "bootstrap"
      ManagedBy  = "terraform"
      Repository = "EamonnHegarty/laidir-infra"
    }
  }
}
