terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "laidir-tfstate-670518205160"
    key          = "global/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project    = "laidir"
      Component  = "global"
      ManagedBy  = "terraform"
      Repository = "EamonnHegarty/laidir-infra"
    }
  }
}
