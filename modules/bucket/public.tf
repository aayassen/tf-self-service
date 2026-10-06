resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = !local.direct
  restrict_public_buckets = !local.direct
}

locals {
  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        # HTTPS only.
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.arn, "${local.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }],
      local.direct ? [{
        # Anyone can download objects, but not list or upload.
        Sid       = "PublicReadObjects"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${local.arn}/*"
      }] : [],
      local.cloudfront ? [{
        # Only this CloudFront distribution can read.
        Sid       = "CloudFrontReadObjects"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${local.arn}/*"
        Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.this[0].arn } }
      }] : [],
    )
  })
}

resource "aws_s3_bucket_policy" "this" {
  bucket     = aws_s3_bucket.this.id
  policy     = local.bucket_policy
  depends_on = [aws_s3_bucket_public_access_block.this]
}
