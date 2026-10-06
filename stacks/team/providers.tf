provider "aws" {
  region = var.region

  # Settings needed by the local emulator.
  s3_use_path_style           = var.aws_emulator
  skip_credentials_validation = var.aws_emulator
  skip_metadata_api_check     = var.aws_emulator
  default_tags {
    tags = {
      "platform:team"        = var.team
      "platform:env"         = var.env
      "platform:cost-center" = local.cfg.owner.cost_center
      "platform:owner"       = local.cfg.owner.github_team
      "platform:managed-by"  = "opentofu/platform"
      "platform:source"      = "teams/${var.team}/${var.env}.yaml"
      "platform:lifecycle"   = local.lifecycle
    }
  }
}
