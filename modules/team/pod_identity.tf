resource "aws_eks_pod_identity_association" "this" {
  count = var.lifecycle_state == "active" && var.enable_pod_identity ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.workload.namespace
  service_account = var.workload.service_account
  role_arn        = aws_iam_role.team[0].arn
  tags            = { "platform:team" = var.team }
}
