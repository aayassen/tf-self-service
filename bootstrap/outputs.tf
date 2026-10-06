output "state_bucket_name" {
  value = aws_s3_bucket.state.bucket
}

output "state_bucket_arn" {
  value = aws_s3_bucket.state.arn
}

output "permissions_boundary_arn" {
  value = aws_iam_policy.team_boundary.arn
}

output "gha_plan_role_arn" {
  value = try(aws_iam_role.gha["plan"].arn, null)
}

output "gha_apply_role_arn" {
  value = try(aws_iam_role.gha["apply"].arn, null)
}

output "tofu_plan_role_arn" {
  value = try(aws_iam_role.tofu["plan"].arn, null)
}

output "tofu_apply_role_arn" {
  value = try(aws_iam_role.tofu["apply"].arn, null)
}
