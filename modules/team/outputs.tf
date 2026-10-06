output "role_arn" {
  value = one(aws_iam_role.team[*].arn)
}

output "role_name" {
  value = one(aws_iam_role.team[*].name)
}

output "buckets" {
  value = { for name, bucket in module.bucket : name => {
    name       = bucket.name
    arn        = bucket.arn
    public_url = bucket.public_url
    visibility = bucket.visibility
  } }
}
