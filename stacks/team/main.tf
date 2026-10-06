locals {
  cfg       = yamldecode(file(var.config_file))
  lifecycle = try(local.cfg.lifecycle, "active")
}

module "team" {
  source = "../../modules/team"

  env                      = var.env
  team                     = var.team
  owner                    = local.cfg.owner
  workload                 = local.cfg.workload
  buckets                  = local.cfg.buckets
  lifecycle_state          = local.lifecycle
  cluster_name             = var.cluster_name
  permissions_boundary_arn = var.permissions_boundary_arn
  enable_pod_identity      = var.enable_pod_identity
  enable_cloudfront        = var.enable_cloudfront
}
