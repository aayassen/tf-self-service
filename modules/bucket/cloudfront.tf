resource "aws_cloudfront_origin_access_control" "this" {
  count = local.cloudfront ? 1 : 0

  name                              = local.name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  count = local.cloudfront ? 1 : 0

  enabled         = true
  is_ipv6_enabled = true
  price_class     = "PriceClass_100"
  tags            = { "platform:team" = var.team }

  origin {
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
    origin_id                = local.name
    origin_access_control_id = aws_cloudfront_origin_access_control.this[0].id
  }

  default_cache_behavior {
    target_origin_id       = local.name
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    # AWS managed "CachingOptimized" policy.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    # The default *.cloudfront.net certificate only allows TLSv1 here; a newer
    # minimum needs a custom domain.
    minimum_protocol_version = "TLSv1"
  }
}
