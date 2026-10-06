output "name" {
  value = aws_s3_bucket.this.bucket
}

output "arn" {
  value = aws_s3_bucket.this.arn
}

output "public_url" {
  value = local.cloudfront ? "https://${aws_cloudfront_distribution.this[0].domain_name}" : (
    local.direct ? "https://${aws_s3_bucket.this.bucket_regional_domain_name}" : null
  )
}

output "visibility" {
  value = local.visibility
}
