terraform {
  required_version = "= 1.13.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # The first apply uses local state. Then switch to backend "s3" {} and run:
  #   tofu init -migrate-state -backend-config=../envs/<env>.backend.hcl -backend-config=key=_bootstrap/terraform.tfstate
  backend "local" {}
}

provider "aws" {
  region = var.region

  # Settings needed by the local emulator.
  s3_use_path_style           = var.aws_emulator
  skip_credentials_validation = var.aws_emulator
  skip_metadata_api_check     = var.aws_emulator

  default_tags {
    tags = {
      "platform:env"        = var.env
      "platform:managed-by" = "opentofu/platform-bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id        = data.aws_caller_identity.current.account_id
  state_bucket_name = var.env == "local" ? "tfstate-local" : "tfstate-${var.env}-${local.account_id}"
  state_bucket_arn  = "arn:aws:s3:::${local.state_bucket_name}"
  boundary_arn      = "arn:aws:iam::${local.account_id}:policy/platform/team-boundary"
}
