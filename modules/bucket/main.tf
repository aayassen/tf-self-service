locals {
  name = "${var.env}-${var.team}-${var.name}"
  arn  = "arn:aws:s3:::${local.name}"
  # A decommissioned bucket is never public.
  visibility = var.lifecycle_state == "decommission" ? "private" : var.visibility
  direct     = local.visibility == "public" && try(var.public.mode == "direct", false)
  cloudfront = local.visibility == "public" && try(var.public.mode == "cloudfront", false) && var.enable_cloudfront
}

resource "aws_s3_bucket" "this" {
  bucket        = local.name
  force_destroy = false
  tags = {
    "platform:bucket"    = var.name
    "platform:lifecycle" = var.lifecycle_state
  }

  lifecycle {
    precondition {
      condition     = !try(var.public.mode == "cloudfront", false) || var.enable_cloudfront
      error_message = "public.mode = cloudfront requires enable_cloudfront = true."
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket     = aws_s3_bucket.this.id
  depends_on = [aws_s3_bucket_versioning.this]
  rule {
    id     = "recovery-and-multipart-cleanup"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
