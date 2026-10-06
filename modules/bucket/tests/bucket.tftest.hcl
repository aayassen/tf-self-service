mock_provider "aws" {}

# Fixed values so the policy JSON and URLs can be checked during a plan.
override_resource {
  target = aws_s3_bucket.this
  values = {
    id                          = "dev-payments-invoices"
    arn                         = "arn:aws:s3:::dev-payments-invoices"
    bucket_regional_domain_name = "dev-payments-invoices.s3.eu-central-1.amazonaws.com"
  }
}
override_resource {
  target = aws_cloudfront_origin_access_control.this[0]
  values = { id = "OAC123" }
}
override_resource {
  target = aws_cloudfront_distribution.this[0]
  values = {
    arn         = "arn:aws:cloudfront::111111111111:distribution/TEST123"
    domain_name = "test123.cloudfront.net"
  }
}

variables {
  env        = "dev"
  team       = "payments"
  name       = "invoices"
  visibility = "private"
}

run "private_baseline" {
  command = plan
  assert {
    condition = (
      output.name == "dev-payments-invoices" &&
      output.arn == "arn:aws:s3:::dev-payments-invoices" &&
      output.public_url == null && output.visibility == "private" &&
      !aws_s3_bucket.this.force_destroy &&
      aws_s3_bucket.this.tags["platform:bucket"] == "invoices" &&
      aws_s3_bucket.this.tags["platform:lifecycle"] == "active"
    )
    error_message = "Names, retention, effective visibility and bucket tags must match the contract."
  }
  assert {
    condition = (
      aws_s3_bucket_public_access_block.this.block_public_acls &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls &&
      aws_s3_bucket_public_access_block.this.block_public_policy &&
      aws_s3_bucket_public_access_block.this.restrict_public_buckets &&
      length(aws_cloudfront_distribution.this) == 0 &&
      length(aws_cloudfront_origin_access_control.this) == 0
    )
    error_message = "Private buckets block all public access and have no CloudFront resources."
  }
  assert {
    condition = jsondecode(aws_s3_bucket_policy.this.policy) == {
      Version = "2012-10-17"
      Statement = [{
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = ["arn:aws:s3:::dev-payments-invoices", "arn:aws:s3:::dev-payments-invoices/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }]
    }
    error_message = "A private bucket has only TLS deny; there must be no anonymous Allow."
  }
  assert {
    condition = (
      one(aws_s3_bucket_ownership_controls.this.rule).object_ownership == "BucketOwnerEnforced" &&
      one(aws_s3_bucket_server_side_encryption_configuration.this.rule).bucket_key_enabled &&
      one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256" &&
      aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled" &&
      aws_s3_bucket_lifecycle_configuration.this.rule[0].status == "Enabled" &&
      aws_s3_bucket_lifecycle_configuration.this.rule[0].noncurrent_version_expiration[0].noncurrent_days == 90 &&
      aws_s3_bucket_lifecycle_configuration.this.rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 7
    )
    error_message = "Every bucket needs ACL-free ownership, SSE-S3, versioning and bounded cleanup."
  }
}

run "direct_public" {
  command = plan
  variables {
    visibility = "public"
    public     = { mode = "direct", justification = "Public development samples" }
  }
  assert {
    condition = (
      length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 2 &&
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Effect == "Deny" &&
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[1] == {
        Sid       = "PublicReadObjects"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::dev-payments-invoices/*"
      }
    )
    error_message = "Direct public grants exactly anonymous GetObject on this bucket's objects."
  }
  assert {
    condition = (
      aws_s3_bucket_public_access_block.this.block_public_acls &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls &&
      !aws_s3_bucket_public_access_block.this.block_public_policy &&
      !aws_s3_bucket_public_access_block.this.restrict_public_buckets &&
      output.public_url == "https://dev-payments-invoices.s3.eu-central-1.amazonaws.com" &&
      output.visibility == "public" && length(aws_cloudfront_distribution.this) == 0
    )
    error_message = "Only policy-level blocks are lowered; direct URL uses the regional HTTPS endpoint."
  }
}

run "cloudfront_public" {
  command = plan
  variables {
    visibility = "public"
    public     = { mode = "cloudfront", justification = "Checkout assets" }
  }
  assert {
    condition = (
      aws_s3_bucket_public_access_block.this.block_public_acls &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls &&
      aws_s3_bucket_public_access_block.this.block_public_policy &&
      aws_s3_bucket_public_access_block.this.restrict_public_buckets &&
      length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 2 &&
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Effect == "Deny" &&
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[1] == {
        Sid       = "CloudFrontReadObjects"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::dev-payments-invoices/*"
        Condition = { StringEquals = { "AWS:SourceArn" = "arn:aws:cloudfront::111111111111:distribution/TEST123" } }
      }
    )
    error_message = "CloudFront keeps S3 private and grants only this distribution read access."
  }
  assert {
    condition = (
      length(aws_cloudfront_origin_access_control.this) == 1 &&
      aws_cloudfront_origin_access_control.this[0].origin_access_control_origin_type == "s3" &&
      aws_cloudfront_origin_access_control.this[0].signing_behavior == "always" &&
      aws_cloudfront_origin_access_control.this[0].signing_protocol == "sigv4" &&
      one(aws_cloudfront_distribution.this[0].origin).origin_access_control_id == "OAC123" &&
      one(aws_cloudfront_distribution.this[0].origin).domain_name == "dev-payments-invoices.s3.eu-central-1.amazonaws.com" &&
      aws_cloudfront_distribution.this[0].tags["platform:team"] == "payments" &&
      aws_cloudfront_distribution.this[0].price_class == "PriceClass_100" &&
      aws_cloudfront_distribution.this[0].default_cache_behavior[0].cache_policy_id == "658327ea-f89d-4fab-a63d-7e88639e58f6" &&
      aws_cloudfront_distribution.this[0].default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https" &&
      aws_cloudfront_distribution.this[0].viewer_certificate[0].cloudfront_default_certificate &&
      aws_cloudfront_distribution.this[0].viewer_certificate[0].minimum_protocol_version == "TLSv1" &&
      output.public_url == "https://test123.cloudfront.net" && output.visibility == "public"
    )
    error_message = "CloudFront must use tagged OAC delivery, managed caching, HTTPS redirects and the default certificate."
  }
}

run "decommission_cloudfront" {
  command = plan
  variables {
    visibility      = "public"
    public          = { mode = "cloudfront", justification = "Retiring assets" }
    lifecycle_state = "decommission"
  }
  assert {
    condition = (
      output.visibility == "private" && output.public_url == null &&
      aws_s3_bucket.this.tags["platform:lifecycle"] == "decommission" &&
      !aws_s3_bucket.this.force_destroy &&
      length(aws_cloudfront_distribution.this) == 0 && length(aws_cloudfront_origin_access_control.this) == 0 &&
      aws_s3_bucket_public_access_block.this.block_public_acls &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls &&
      aws_s3_bucket_public_access_block.this.block_public_policy &&
      aws_s3_bucket_public_access_block.this.restrict_public_buckets &&
      length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 1 &&
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Effect == "Deny"
    )
    error_message = "Decommission must retain the bucket, revoke public access and drop CloudFront/OAC."
  }
}

run "decommission_direct" {
  command = plan
  variables {
    visibility      = "public"
    public          = { mode = "direct", justification = "Retiring samples" }
    lifecycle_state = "decommission"
  }
  assert {
    condition = (
      output.visibility == "private" && output.public_url == null &&
      aws_s3_bucket_public_access_block.this.block_public_acls &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls &&
      aws_s3_bucket_public_access_block.this.block_public_policy &&
      aws_s3_bucket_public_access_block.this.restrict_public_buckets &&
      length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 1
    )
    error_message = "Decommission must also remove direct anonymous read access."
  }
}

run "missing_visibility" {
  command = plan
  variables { visibility = null }
  expect_failures = [var.visibility]
}

run "invalid_visibility" {
  command = plan
  variables { visibility = "internal" }
  expect_failures = [var.visibility]
}

run "missing_public_settings" {
  command = plan
  variables { visibility = "public" }
  expect_failures = [var.public]
}

run "private_forbids_public_settings" {
  command = plan
  variables { public = { mode = "direct", justification = "Invalid private setting" } }
  expect_failures = [var.public]
}

run "cloudfront_disabled" {
  command = plan
  variables {
    visibility        = "public"
    public            = { mode = "cloudfront", justification = "Unsupported locally" }
    enable_cloudfront = false
  }
  expect_failures = [aws_s3_bucket.this]
}

run "direct_without_cloudfront" {
  command = plan
  variables {
    visibility        = "public"
    public            = { mode = "direct", justification = "Direct requires no CloudFront" }
    enable_cloudfront = false
  }
  assert {
    condition     = output.visibility == "public" && length(aws_cloudfront_distribution.this) == 0
    error_message = "Disabling CloudFront must still allow direct public buckets."
  }
}
