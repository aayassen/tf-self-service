data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  cluster_arn        = "arn:aws:eks:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
  active_bucket_arns = [for name in sort(keys(local.active_buckets)) : "arn:aws:s3:::${var.env}-${var.team}-${name}"]
  trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      # Only the team's app on EKS can use this role.
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnEquals    = { "aws:SourceArn" = local.cluster_arn }
      }
    }]
  })
  s3_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
        Resource = local.active_bucket_arns
      },
      {
        # No deleting old versions, so data can always be recovered.
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        Resource = [for arn in local.active_bucket_arns : "${arn}/*"]
      },
    ]
  })
}

resource "aws_iam_role" "team" {
  count = var.lifecycle_state == "active" ? 1 : 0

  name                 = "${var.env}-team-${var.team}"
  path                 = "/teams/"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy   = local.trust_policy
  tags                 = { "platform:team" = var.team }
}

resource "aws_iam_role_policy" "s3" {
  count = length(local.active_buckets) > 0 ? 1 : 0

  name   = "active-buckets"
  role   = aws_iam_role.team[0].name
  policy = local.s3_policy
}
