resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_ci_identity ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # No certificate thumbprint needed; AWS trusts GitHub's certificate already.
}

locals {
  ci_modes = var.enable_ci_identity ? toset(["plan", "apply"]) : toset([])
  gha_trust = { for mode in local.ci_modes : mode => jsonencode({
    Version = "2012-10-17"
    Statement = [{
      # PRs and main can plan. Apply needs the GitHub environment, so restrict the
      # dev/staging/prod environments to the main branch in the repo settings.
      Sid       = "GitHubOIDC"
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github[0].arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = merge(
        { StringEquals = merge(
          { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" },
          mode == "apply" ? { "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:environment:${var.env}" } : {}
        ) },
        mode == "plan" ? { StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.github_repo}:pull_request",
            "repo:${var.github_repo}:ref:refs/heads/main",
          ]
        } } : {}
      )
    }]
  }) }
}
