# Allow public bucket policies at account level, for "direct" public buckets.
# Every private bucket still blocks public access on its own.
resource "aws_s3_account_public_access_block" "this" {
  count = var.enable_ci_identity ? 1 : 0

  account_id              = local.account_id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_ce_cost_allocation_tag" "platform" {
  for_each = var.enable_ci_identity ? toset(["platform:team", "platform:env", "platform:cost-center"]) : toset([])

  tag_key = each.value
  status  = "Active"
}
