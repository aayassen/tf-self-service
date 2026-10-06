locals {
  team_state_prefix = "teams/$${aws:PrincipalTag/team}/"
  team_bucket_arn   = "arn:aws:s3:::${var.env}-$${aws:PrincipalTag/team}-*"
  team_role_arn     = "arn:aws:iam::${local.account_id}:role/teams/${var.env}-team-$${aws:PrincipalTag/team}"
  cluster_arn       = "arn:aws:eks:${var.region}:${local.account_id}:cluster/${var.cluster_name}"
  association_arn   = "arn:aws:eks:${var.region}:${local.account_id}:podidentityassociation/${var.cluster_name}/*"
  distribution_arn  = "arn:aws:cloudfront::${local.account_id}:distribution/*"
  request_team      = { StringEquals = { "aws:RequestTag/platform:team" = "$${aws:PrincipalTag/team}" } }
  resource_team     = { StringEquals = { "aws:ResourceTag/platform:team" = "$${aws:PrincipalTag/team}" } }

  executor_trust = { for mode in local.ci_modes : mode => jsonencode({
    Version = "2012-10-17"
    Statement = [{
      # Only the CI entry role, and it must set a team tag.
      Sid       = "TaggedGitHubSession"
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.gha[mode].arn }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringLike                  = { "aws:RequestTag/team" = "?*" }
        "ForAllValues:StringEquals" = { "aws:TagKeys" = ["team"] }
      }
    }]
  }) }

  gha_permissions = { for mode in local.ci_modes : mode => jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AssumeMatchingExecutor"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole", "sts:TagSession"]
        Resource = aws_iam_role.tofu[mode].arn
      },
      {
        # The applied-SHA marker.
        Sid      = "AppliedSHAMarker"
        Effect   = "Allow"
        Action   = mode == "plan" ? ["s3:GetObject"] : ["s3:GetObject", "s3:PutObject"]
        Resource = "${local.state_bucket_arn}/_meta/*"
      },
    ]
  }) }

  executor_read_statements = [
    {
      # Only this team's state and lock file.
      Sid      = "ReadTeamState"
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${local.state_bucket_arn}/${local.team_state_prefix}*"
    },
    {
      Sid       = "ListTeamState"
      Effect    = "Allow"
      Action    = ["s3:ListBucket"]
      Resource  = local.state_bucket_arn
      Condition = { StringLike = { "s3:prefix" = [local.team_state_prefix, "${local.team_state_prefix}*"] } }
    },
    {
      Sid    = "ReadTeamBuckets"
      Effect = "Allow"
      Action = [
        "s3:ListBucket", "s3:ListBucketVersions", "s3:GetBucketLocation", "s3:GetBucketAcl",
        "s3:GetBucketPolicy", "s3:GetBucketPolicyStatus", "s3:GetBucketPublicAccessBlock",
        "s3:GetBucketVersioning", "s3:GetEncryptionConfiguration", "s3:GetBucketTagging",
        "s3:GetLifecycleConfiguration", "s3:GetBucketOwnershipControls",
        "s3:GetBucketCORS", "s3:GetBucketWebsite", "s3:GetBucketLogging",
        "s3:GetReplicationConfiguration", "s3:GetAccelerateConfiguration",
        "s3:GetBucketRequestPayment", "s3:GetBucketObjectLockConfiguration",
      ]
      Resource = local.team_bucket_arn
    },
    {
      Sid      = "ReadTeamRole"
      Effect   = "Allow"
      Action   = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListRoleTags", "iam:ListInstanceProfilesForRole"]
      Resource = local.team_role_arn
    },
    {
      Sid      = "ReadCluster"
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster", "eks:ListPodIdentityAssociations"]
      Resource = local.cluster_arn
    },
    {
      Sid       = "ReadTeamAssociations"
      Effect    = "Allow"
      Action    = ["eks:DescribePodIdentityAssociation", "eks:ListTagsForResource"]
      Resource  = local.association_arn
      Condition = local.resource_team
    },
    {
      Sid       = "ReadTeamDistributions"
      Effect    = "Allow"
      Action    = ["cloudfront:GetDistribution", "cloudfront:GetDistributionConfig", "cloudfront:ListTagsForResource"]
      Resource  = local.distribution_arn
      Condition = local.resource_team
    },
    {
      # OACs can't be tagged or scoped, so this has to be "*".
      Sid      = "ReadOriginAccessControls"
      Effect   = "Allow"
      Action   = ["cloudfront:GetOriginAccessControl", "cloudfront:GetOriginAccessControlConfig"]
      Resource = "*"
    },
  ]

  executor_write_statements = [
    {
      Sid      = "WriteTeamState"
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = "${local.state_bucket_arn}/${local.team_state_prefix}*"
    },
    {
      # Bucket settings only, never object data.
      Sid    = "ManageTeamBuckets"
      Effect = "Allow"
      Action = [
        "s3:CreateBucket", "s3:DeleteBucket", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy",
        "s3:PutBucketPublicAccessBlock", "s3:PutBucketVersioning",
        "s3:PutEncryptionConfiguration", "s3:PutBucketTagging",
        "s3:PutLifecycleConfiguration", "s3:PutBucketOwnershipControls",
        "s3:DeleteBucketOwnershipControls",
      ]
      Resource = local.team_bucket_arn
    },
    {
      # New team roles must get the boundary and the team tag.
      Sid      = "CreateBoundedTeamRole"
      Effect   = "Allow"
      Action   = ["iam:CreateRole"]
      Resource = local.team_role_arn
      Condition = { StringEquals = {
        "iam:PermissionsBoundary"      = local.boundary_arn
        "aws:RequestTag/platform:team" = "$${aws:PrincipalTag/team}"
      } }
    },
    {
      Sid      = "ManageTeamRole"
      Effect   = "Allow"
      Action   = ["iam:DeleteRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:UpdateAssumeRolePolicy", "iam:UntagRole"]
      Resource = local.team_role_arn
    },
    {
      Sid       = "TagTeamRole"
      Effect    = "Allow"
      Action    = ["iam:TagRole"]
      Resource  = local.team_role_arn
      Condition = { StringEqualsIfExists = { "aws:RequestTag/platform:team" = "$${aws:PrincipalTag/team}" } }
    },
    {
      Sid       = "PassTeamRoleToPods"
      Effect    = "Allow"
      Action    = ["iam:PassRole"]
      Resource  = local.team_role_arn
      Condition = { StringEquals = { "iam:PassedToService" = "pods.eks.amazonaws.com" } }
    },
    {
      Sid       = "CreateTeamAssociation"
      Effect    = "Allow"
      Action    = ["eks:CreatePodIdentityAssociation"]
      Resource  = local.cluster_arn
      Condition = local.request_team
    },
    {
      Sid       = "ManageTeamAssociations"
      Effect    = "Allow"
      Action    = ["eks:UpdatePodIdentityAssociation", "eks:DeletePodIdentityAssociation", "eks:UntagResource"]
      Resource  = local.association_arn
      Condition = local.resource_team
    },
    {
      Sid      = "TagTeamAssociations"
      Effect   = "Allow"
      Action   = ["eks:TagResource"]
      Resource = local.association_arn
      Condition = {
        StringEquals         = { "aws:RequestTag/platform:team" = "$${aws:PrincipalTag/team}" }
        StringEqualsIfExists = { "aws:ResourceTag/platform:team" = "$${aws:PrincipalTag/team}" }
      }
    },
    {
      Sid       = "CreateTeamDistribution"
      Effect    = "Allow"
      Action    = ["cloudfront:CreateDistributionWithTags"]
      Resource  = local.distribution_arn
      Condition = local.request_team
    },
    {
      Sid       = "ManageTeamDistributions"
      Effect    = "Allow"
      Action    = ["cloudfront:UpdateDistribution", "cloudfront:DeleteDistribution", "cloudfront:UntagResource"]
      Resource  = local.distribution_arn
      Condition = local.resource_team
    },
    {
      Sid      = "TagTeamDistributions"
      Effect   = "Allow"
      Action   = ["cloudfront:TagResource"]
      Resource = local.distribution_arn
      Condition = {
        StringEquals         = { "aws:RequestTag/platform:team" = "$${aws:PrincipalTag/team}" }
        StringEqualsIfExists = { "aws:ResourceTag/platform:team" = "$${aws:PrincipalTag/team}" }
      }
    },
    {
      # Known risk: one team's run could change another team's OAC. That can break
      # their CloudFront, but never gives access to their data.
      Sid      = "ManageOriginAccessControls"
      Effect   = "Allow"
      Action   = ["cloudfront:CreateOriginAccessControl", "cloudfront:UpdateOriginAccessControl", "cloudfront:DeleteOriginAccessControl"]
      Resource = "*"
    },
  ]

  executor_deny_statements = [
    {
      Sid      = "DenyBoundaryAndManagedPolicyChanges"
      Effect   = "Deny"
      Action   = ["iam:PutRolePermissionsBoundary", "iam:DeleteRolePermissionsBoundary", "iam:AttachRolePolicy"]
      Resource = "arn:aws:iam::${local.account_id}:role/*"
    },
    {
      Sid      = "DenyPersistentCredentials"
      Effect   = "Deny"
      Action   = ["iam:CreateUser", "iam:CreateAccessKey"]
      Resource = "arn:aws:iam::${local.account_id}:user/*"
    },
    {
      Sid    = "DenyPlatformIAMChanges"
      Effect = "Deny"
      Action = ["iam:*"]
      Resource = [for kind in ["role", "policy", "user", "group", "instance-profile"] :
        "arn:aws:iam::${local.account_id}:${kind}/platform/*"
      ]
    },
    {
      # Removing the team tag would break the isolation above.
      Sid       = "DenyRemovingOwnershipTag"
      Effect    = "Deny"
      Action    = ["iam:UntagRole", "eks:UntagResource", "cloudfront:UntagResource"]
      Resource  = [local.team_role_arn, local.association_arn, local.distribution_arn]
      Condition = { "ForAnyValue:StringEquals" = { "aws:TagKeys" = ["platform:team"] } }
    },
  ]

  executor_permissions = { for mode in local.ci_modes : mode => jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      local.executor_read_statements,
      [for statement in local.executor_write_statements : statement if mode == "apply"],
      local.executor_deny_statements,
    )
  }) }
}

resource "aws_iam_role" "gha" {
  for_each = local.ci_modes

  name               = "gha-${each.key}-${var.env}"
  assume_role_policy = local.gha_trust[each.key]
}

resource "aws_iam_role" "tofu" {
  for_each = local.ci_modes

  name               = "tofu-${each.key}-${var.env}"
  assume_role_policy = local.executor_trust[each.key]
}

resource "aws_iam_role_policy" "gha" {
  for_each = local.ci_modes

  name   = "executor-and-marker"
  role   = aws_iam_role.gha[each.key].id
  policy = local.gha_permissions[each.key]
}

resource "aws_iam_role_policy" "tofu" {
  for_each = local.ci_modes

  name   = "team-abac"
  role   = aws_iam_role.tofu[each.key].id
  policy = local.executor_permissions[each.key]
}
