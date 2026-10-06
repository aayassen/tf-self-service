mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
      arn        = "arn:aws:iam::111111111111:user/mock-admin"
      user_id    = "mock-admin"
    }
  }
}

# Fixed values so the policy JSON can be checked during a plan.
override_resource {
  target = aws_iam_openid_connect_provider.github[0]
  values = { arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com" }
}

override_resource {
  target = aws_iam_role.gha["plan"]
  values = { arn = "arn:aws:iam::111111111111:role/gha-plan-dev" }
}

override_resource {
  target = aws_iam_role.gha["apply"]
  values = { arn = "arn:aws:iam::111111111111:role/gha-apply-dev" }
}

override_resource {
  target = aws_iam_role.tofu["plan"]
  values = { arn = "arn:aws:iam::111111111111:role/tofu-plan-dev" }
}

override_resource {
  target = aws_iam_role.tofu["apply"]
  values = { arn = "arn:aws:iam::111111111111:role/tofu-apply-dev" }
}

override_resource {
  target = aws_iam_policy.team_boundary
  values = { arn = "arn:aws:iam::111111111111:policy/platform/team-boundary" }
}

override_resource {
  target = aws_s3_bucket.state
  values = {
    arn = "arn:aws:s3:::tfstate-dev-111111111111"
    id  = "tfstate-dev-111111111111"
  }
}

variables {
  env                = "dev"
  region             = "eu-central-1"
  github_repo        = "my-org/platform"
  cluster_name       = "dev"
  enable_ci_identity = true
}

run "state_and_boundary" {
  command = plan

  assert {
    condition     = aws_s3_bucket.state.bucket == "tfstate-dev-111111111111" && !aws_s3_bucket.state.force_destroy
    error_message = "State bucket must use the account-qualified name and retain nonempty data."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.state.block_public_acls &&
      aws_s3_bucket_public_access_block.state.ignore_public_acls &&
      aws_s3_bucket_public_access_block.state.block_public_policy &&
      aws_s3_bucket_public_access_block.state.restrict_public_buckets
    )
    error_message = "State must block every form of public access."
  }

  assert {
    condition = (
      jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Effect == "Deny" &&
      jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Principal == "*" &&
      jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Action == "*" &&
      jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false" &&
      toset(jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Resource) == toset([
        "arn:aws:s3:::tfstate-dev-111111111111", "arn:aws:s3:::tfstate-dev-111111111111/*"
      ])
    )
    error_message = "TLS deny must cover the state bucket and every object."
  }

  assert {
    condition = (
      aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled" &&
      one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256" &&
      one(aws_s3_bucket_server_side_encryption_configuration.state.rule).bucket_key_enabled &&
      one(aws_s3_bucket_ownership_controls.state.rule).object_ownership == "BucketOwnerEnforced" &&
      aws_s3_bucket_lifecycle_configuration.state.rule[0].noncurrent_version_expiration[0].noncurrent_days == 90
    )
    error_message = "State recovery, encryption and ACL controls must match the baseline."
  }

  assert {
    condition = (
      aws_iam_policy.team_boundary.path == "/platform/" &&
      aws_iam_policy.team_boundary.name == "team-boundary" &&
      jsondecode(aws_iam_policy.team_boundary.policy).Statement[0].Effect == "Allow" &&
      toset(jsondecode(aws_iam_policy.team_boundary.policy).Statement[0].Resource) == toset([
        "arn:aws:s3:::dev-$${aws:PrincipalTag/platform:team}-*",
        "arn:aws:s3:::dev-$${aws:PrincipalTag/platform:team}-*/*"
      ]) &&
      toset(jsondecode(aws_iam_policy.team_boundary.policy).Statement[0].Action) == toset([
        "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
        "s3:GetBucketLocation", "s3:ListBucketMultipartUploads", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"
      ])
    )
    error_message = "Boundary must cap team roles to their own prefix and data-plane actions."
  }

  assert {
    condition = (
      aws_s3_account_public_access_block.this[0].block_public_acls &&
      aws_s3_account_public_access_block.this[0].ignore_public_acls &&
      !aws_s3_account_public_access_block.this[0].block_public_policy &&
      !aws_s3_account_public_access_block.this[0].restrict_public_buckets &&
      toset(keys(aws_ce_cost_allocation_tag.platform)) == toset(["platform:team", "platform:env", "platform:cost-center"]) &&
      alltrue([for tag in aws_ce_cost_allocation_tag.platform : tag.status == "Active"])
    )
    error_message = "Account controls must support direct-public buckets, ownership and cost allocation."
  }
}

run "ci_identity_and_abac" {
  command = plan

  assert {
    condition = (
      aws_iam_openid_connect_provider.github[0].url == "https://token.actions.githubusercontent.com" &&
      toset(aws_iam_openid_connect_provider.github[0].client_id_list) == toset(["sts.amazonaws.com"]) &&
      toset(jsondecode(aws_iam_role.gha["plan"].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"]) == toset([
        "repo:my-org/platform:pull_request", "repo:my-org/platform:ref:refs/heads/main"
      ]) &&
      jsondecode(aws_iam_role.gha["apply"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:my-org/platform:environment:dev" &&
      alltrue([for mode in ["plan", "apply"] :
        jsondecode(aws_iam_role.gha[mode].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com" &&
        jsondecode(aws_iam_role.gha[mode].assume_role_policy).Statement[0].Principal.Federated == "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com" &&
        jsondecode(aws_iam_role.gha[mode].assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
      ])
    )
    error_message = "GitHub trust must bind audience, repository, plan contexts and apply environment."
  }

  assert {
    condition = alltrue([for mode in ["plan", "apply"] :
      length(jsondecode(aws_iam_role_policy.gha[mode].policy).Statement) == 2 &&
      jsondecode(aws_iam_role_policy.gha[mode].policy).Statement[0].Effect == "Allow" &&
      toset(jsondecode(aws_iam_role_policy.gha[mode].policy).Statement[0].Action) == toset(["sts:AssumeRole", "sts:TagSession"]) &&
      jsondecode(aws_iam_role_policy.gha[mode].policy).Statement[0].Resource == "arn:aws:iam::111111111111:role/tofu-${mode}-dev" &&
      jsondecode(aws_iam_role_policy.gha[mode].policy).Statement[1].Resource == "arn:aws:s3:::tfstate-dev-111111111111/_meta/*" &&
      toset(jsondecode(aws_iam_role_policy.gha[mode].policy).Statement[1].Action) == toset(mode == "plan" ? ["s3:GetObject"] : ["s3:GetObject", "s3:PutObject"])
    ])
    error_message = "Each GHA role may only assume its matching executor and access the applied-SHA marker."
  }

  assert {
    condition = alltrue([for mode in ["plan", "apply"] :
      length(jsondecode(aws_iam_role.tofu[mode].assume_role_policy).Statement) == 1 &&
      jsondecode(aws_iam_role.tofu[mode].assume_role_policy).Statement[0].Principal.AWS == "arn:aws:iam::111111111111:role/gha-${mode}-dev" &&
      toset(jsondecode(aws_iam_role.tofu[mode].assume_role_policy).Statement[0].Action) == toset(["sts:AssumeRole", "sts:TagSession"]) &&
      jsondecode(aws_iam_role.tofu[mode].assume_role_policy).Statement[0].Condition.StringLike["aws:RequestTag/team"] == "?*" &&
      toset(jsondecode(aws_iam_role.tofu[mode].assume_role_policy).Statement[0].Condition["ForAllValues:StringEquals"]["aws:TagKeys"]) == toset(["team"])
    ])
    error_message = "Executor trust must require exactly the team tag from the matching entry role."
  }

  assert {
    condition = length([for statement in jsondecode(aws_iam_role_policy.tofu["apply"].policy).Statement : statement
      if contains(["ReadTeamState", "WriteTeamState", "ListTeamState"], statement.Sid)
      ]) == 3 && alltrue([for statement in jsondecode(aws_iam_role_policy.tofu["apply"].policy).Statement :
      statement.Resource == "arn:aws:s3:::tfstate-dev-111111111111/teams/$${aws:PrincipalTag/team}/*"
      if contains(["ReadTeamState", "WriteTeamState"], statement.Sid)
      ]) && alltrue([for statement in jsondecode(aws_iam_role_policy.tofu["apply"].policy).Statement :
      statement.Resource == "arn:aws:s3:::tfstate-dev-111111111111" &&
      toset(statement.Condition.StringLike["s3:prefix"]) == toset(["teams/$${aws:PrincipalTag/team}/", "teams/$${aws:PrincipalTag/team}/*"])
      if statement.Sid == "ListTeamState"
    ])
    error_message = "State read/write/list access must be restricted to the tagged team's prefix."
  }

  assert {
    condition = length([for statement in jsondecode(aws_iam_role_policy.tofu["apply"].policy).Statement : statement
      if contains(statement.Action, "iam:CreateRole")
      ]) == 1 && alltrue([for statement in jsondecode(aws_iam_role_policy.tofu["apply"].policy).Statement :
      statement.Resource == "arn:aws:iam::111111111111:role/teams/dev-team-$${aws:PrincipalTag/team}" &&
      statement.Condition.StringEquals["iam:PermissionsBoundary"] == "arn:aws:iam::111111111111:policy/platform/team-boundary" &&
      statement.Condition.StringEquals["aws:RequestTag/platform:team"] == "$${aws:PrincipalTag/team}"
      if contains(statement.Action, "iam:CreateRole")
    ])
    error_message = "CreateRole must require the platform boundary and matching ownership tag."
  }

  assert {
    condition = alltrue([for mode in ["plan", "apply"] : alltrue([
      for action in ["iam:PutRolePermissionsBoundary", "iam:DeleteRolePermissionsBoundary", "iam:AttachRolePolicy", "iam:CreateUser", "iam:CreateAccessKey"] :
      anytrue([for statement in jsondecode(aws_iam_role_policy.tofu[mode].policy).Statement :
        statement.Effect == "Deny" && contains(statement.Action, action)
      ])
    ])])
    error_message = "Executors must explicitly deny boundary changes, managed policies and persistent credentials."
  }

  assert {
    condition = alltrue([for statement in jsondecode(aws_iam_role_policy.tofu["plan"].policy).Statement :
      alltrue([for action in statement.Action : can(regex("^[^:]+:(Get|List|Describe)", action))])
      if statement.Effect == "Allow"
    ])
    error_message = "The plan role must be read-only."
  }

  assert {
    condition = length([for statement in jsondecode(aws_iam_role_policy.tofu["apply"].policy).Statement : statement
      if contains(statement.Action, "iam:PassRole")
      ]) == 1 && alltrue([for statement in jsondecode(aws_iam_role_policy.tofu["apply"].policy).Statement :
      statement.Resource == "arn:aws:iam::111111111111:role/teams/dev-team-$${aws:PrincipalTag/team}" &&
      statement.Condition.StringEquals["iam:PassedToService"] == "pods.eks.amazonaws.com"
      if contains(statement.Action, "iam:PassRole")
      ]) && alltrue([for statement in jsondecode(aws_iam_role_policy.tofu["apply"].policy).Statement :
      statement.Resource == "arn:aws:s3:::dev-$${aws:PrincipalTag/team}-*"
      if contains(["ReadTeamBuckets", "ManageTeamBuckets"], statement.Sid)
    ])
    error_message = "Team resource names and PassRole must not escape the session scope."
  }

  assert {
    condition = alltrue([for statement in jsondecode(aws_iam_role_policy.tofu["apply"].policy).Statement :
      try(statement.Condition.StringEquals["aws:RequestTag/platform:team"] == "$${aws:PrincipalTag/team}", false) ||
      try(statement.Condition.StringEquals["aws:ResourceTag/platform:team"] == "$${aws:PrincipalTag/team}", false)
      if statement.Effect == "Allow" && anytrue([for action in statement.Action : startswith(action, "cloudfront:")]) && statement.Resource != "*"
    ])
    error_message = "CloudFront distribution grants must retain the ownership-tag gate (untaggable OAC APIs are the documented exception)."
  }

  assert {
    condition = alltrue([for mode in ["plan", "apply"] : alltrue([
      for statement in jsondecode(aws_iam_role_policy.tofu[mode].policy).Statement :
      !contains(statement.Action, "s3:*") && (
        statement.Effect == "Deny" || statement.Resource != "*" ||
        alltrue([for action in statement.Action : contains([
          "cloudfront:GetOriginAccessControl", "cloudfront:GetOriginAccessControlConfig",
          "cloudfront:CreateOriginAccessControl", "cloudfront:UpdateOriginAccessControl", "cloudfront:DeleteOriginAccessControl"
        ], action)])
      )
    ])])
    error_message = "Unscoped grants are reserved for the documented OAC API exceptions; s3:* is forbidden."
  }

  assert {
    condition = alltrue([for mode in ["plan", "apply"] :
      length(replace(aws_iam_role_policy.tofu[mode].policy, "/\\s/", "")) <= 10240
    ])
    error_message = "Executor inline policies must fit the IAM role's 10,240-character aggregate limit."
  }
}

run "local_omits_ci_and_account_controls" {
  command = plan

  variables {
    env                = "local"
    cluster_name       = "local"
    enable_ci_identity = false
  }

  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "123456789012" }
  }

  override_resource {
    target = aws_s3_bucket.state
    values = {
      arn = "arn:aws:s3:::tfstate-local"
      id  = "tfstate-local"
    }
  }

  override_resource {
    target = aws_iam_policy.team_boundary
    values = { arn = "arn:aws:iam::123456789012:policy/platform/team-boundary" }
  }

  assert {
    condition = (
      length(aws_iam_openid_connect_provider.github) == 0 &&
      length(aws_iam_role.gha) == 0 && length(aws_iam_role.tofu) == 0 &&
      length(aws_iam_role_policy.gha) == 0 && length(aws_iam_role_policy.tofu) == 0 &&
      length(aws_s3_account_public_access_block.this) == 0 &&
      length(aws_ce_cost_allocation_tag.platform) == 0
    )
    error_message = "The emulator must omit OIDC, all CI identities/policies and account-only controls."
  }

  assert {
    condition = (
      output.state_bucket_name == "tfstate-local" &&
      output.state_bucket_arn == "arn:aws:s3:::tfstate-local" &&
      output.permissions_boundary_arn == "arn:aws:iam::123456789012:policy/platform/team-boundary" &&
      output.gha_plan_role_arn == null && output.gha_apply_role_arn == null &&
      output.tofu_plan_role_arn == null && output.tofu_apply_role_arn == null &&
      toset(jsondecode(aws_iam_policy.team_boundary.policy).Statement[0].Resource) == toset([
        "arn:aws:s3:::local-$${aws:PrincipalTag/platform:team}-*",
        "arn:aws:s3:::local-$${aws:PrincipalTag/platform:team}-*/*"
      ])
    )
    error_message = "Local must retain its state bucket and boundary while returning null CI role ARNs."
  }
}
