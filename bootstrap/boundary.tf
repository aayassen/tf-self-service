locals {
  boundary_bucket_prefix = "arn:aws:s3:::${var.env}-$${aws:PrincipalTag/platform:team}-*"
  team_boundary_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      # The most a team role can ever do: read/write objects in its own buckets.
      Sid    = "TeamS3DataOnly"
      Effect = "Allow"
      Action = [
        "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
        "s3:GetBucketLocation", "s3:ListBucketMultipartUploads",
        "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts",
      ]
      Resource = [local.boundary_bucket_prefix, "${local.boundary_bucket_prefix}/*"]
    }]
  })
}

resource "aws_iam_policy" "team_boundary" {
  name        = "team-boundary"
  path        = "/platform/"
  description = "Team S3 data-plane ceiling; attached by the team stack."
  policy      = local.team_boundary_policy
}
