locals {
  # Grouped so duplicate names hit the friendly validation error.
  buckets_by_name = { for bucket in var.buckets : bucket.name => bucket... }
  active_buckets = {
    for name, buckets in local.buckets_by_name : name => buckets[0]
    if var.lifecycle_state == "active" && buckets[0].lifecycle == "active"
  }
}

module "bucket" {
  source   = "../bucket"
  for_each = local.buckets_by_name

  env               = var.env
  team              = var.team
  name              = each.key
  visibility        = each.value[0].visibility
  public            = each.value[0].public
  lifecycle_state   = var.lifecycle_state == "decommission" ? "decommission" : each.value[0].lifecycle
  enable_cloudfront = var.enable_cloudfront
}
