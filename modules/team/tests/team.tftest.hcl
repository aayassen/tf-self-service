mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_region" {
    defaults = { region = "eu-central-1" }
  }
}

override_resource {
  target = aws_iam_role.team[0]
  values = { arn = "arn:aws:iam::111111111111:role/teams/dev-team-payments" }
}

variables {
  env                      = "dev"
  team                     = "payments"
  owner                    = { github_team = "my-org/payments", contact = "#payments-eng", cost_center = "CC-1042" }
  workload                 = { namespace = "payments", service_account = "payments-api" }
  cluster_name             = "dev"
  permissions_boundary_arn = "arn:aws:iam::111111111111:policy/platform/team-boundary"
  buckets = [
    { name = "invoices", visibility = "private" },
    { name = "exports", visibility = "private" },
    { name = "old-assets", visibility = "public", public = { mode = "cloudfront", justification = "Retiring assets" }, lifecycle = "decommission" },
  ]
}

run "active_role_and_buckets" {
  command = plan
  assert {
    condition = (
      aws_iam_role.team[0].name == "dev-team-payments" &&
      aws_iam_role.team[0].path == "/teams/" &&
      aws_iam_role.team[0].permissions_boundary == "arn:aws:iam::111111111111:policy/platform/team-boundary" &&
      aws_iam_role.team[0].tags["platform:team"] == "payments" &&
      output.role_name == "dev-team-payments" &&
      output.role_arn == "arn:aws:iam::111111111111:role/teams/dev-team-payments"
    )
    error_message = "The role must fit the executor's name/path, boundary and tag requirements."
  }
  assert {
    condition = jsondecode(aws_iam_role.team[0].assume_role_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Service = "pods.eks.amazonaws.com" }
        Action    = ["sts:AssumeRole", "sts:TagSession"]
        Condition = {
          StringEquals = { "aws:SourceAccount" = "111111111111" }
          ArnEquals    = { "aws:SourceArn" = "arn:aws:eks:eu-central-1:111111111111:cluster/dev" }
        }
      }]
    }
    error_message = "Pod Identity trust must bind the service, account and exact cluster."
  }
  assert {
    condition = jsondecode(aws_iam_role_policy.s3[0].policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
          Resource = ["arn:aws:s3:::dev-payments-exports", "arn:aws:s3:::dev-payments-invoices"]
        },
        {
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
          Resource = ["arn:aws:s3:::dev-payments-exports/*", "arn:aws:s3:::dev-payments-invoices/*"]
        },
      ]
    }
    error_message = "Policy must contain exactly the active ARNs and data-plane actions, excluding old-assets and DeleteObjectVersion."
  }
  assert {
    condition = (
      aws_eks_pod_identity_association.this[0].cluster_name == "dev" &&
      aws_eks_pod_identity_association.this[0].namespace == "payments" &&
      aws_eks_pod_identity_association.this[0].service_account == "payments-api" &&
      aws_eks_pod_identity_association.this[0].role_arn == output.role_arn &&
      aws_eks_pod_identity_association.this[0].tags["platform:team"] == "payments"
    )
    error_message = "The tagged association must bind the requested workload to this team's role."
  }
  assert {
    condition = (
      toset(keys(module.bucket)) == toset(["invoices", "exports", "old-assets"]) &&
      output.buckets["invoices"].name == "dev-payments-invoices" &&
      output.buckets["old-assets"].visibility == "private" &&
      output.buckets["old-assets"].public_url == null
    )
    error_message = "Buckets need stable name keys and decommissioned buckets must report private visibility."
  }
}

run "add_bucket_preserves_keys" {
  command = plan
  variables {
    buckets = [
      { name = "new-bucket", visibility = "private" },
      { name = "exports", visibility = "private" },
      { name = "invoices", visibility = "private" },
      { name = "old-assets", visibility = "private", lifecycle = "decommission" },
    ]
  }
  assert {
    condition = (
      toset(keys(module.bucket)) == toset(["invoices", "exports", "old-assets", "new-bucket"]) &&
      # Same buckets in a different order: nothing should be replaced.
      output.buckets["invoices"].name == "dev-payments-invoices" &&
      output.buckets["exports"].name == "dev-payments-exports" &&
      toset(jsondecode(aws_iam_role_policy.s3[0].policy).Statement[0].Resource) == toset([
        "arn:aws:s3:::dev-payments-invoices", "arn:aws:s3:::dev-payments-exports", "arn:aws:s3:::dev-payments-new-bucket"
      ])
    )
    error_message = "Adding/reordering buckets must preserve existing module keys and exact resource names."
  }
}

run "team_decommission" {
  command = plan
  variables {
    lifecycle_state = "decommission"
    buckets = [
      { name = "invoices", visibility = "private" },
      { name = "assets", visibility = "public", public = { mode = "cloudfront", justification = "Retiring CDN" } },
      { name = "samples", visibility = "public", public = { mode = "direct", justification = "Retiring samples" } },
    ]
  }
  assert {
    condition = (
      length(aws_iam_role.team) == 0 && length(aws_iam_role_policy.s3) == 0 &&
      length(aws_eks_pod_identity_association.this) == 0 &&
      output.role_arn == null && output.role_name == null &&
      length(output.buckets) == 3 &&
      alltrue([for bucket in output.buckets : bucket.visibility == "private" && bucket.public_url == null])
    )
    error_message = "Team decommission removes identity/policy/association and makes every retained bucket private."
  }
}

run "empty_decommissioned_team" {
  command = plan
  variables {
    lifecycle_state = "decommission"
    buckets         = []
  }
  assert {
    condition     = length(aws_iam_role_policy.s3) == 0 && length(output.buckets) == 0 && output.role_name == null
    error_message = "An empty decommissioning team must not generate an empty IAM policy or role."
  }
}

run "pod_identity_disabled" {
  command = plan
  variables { enable_pod_identity = false }
  assert {
    condition     = length(aws_eks_pod_identity_association.this) == 0 && length(aws_iam_role.team) == 1 && length(aws_iam_role_policy.s3) == 1
    error_message = "The local feature flag omits only the Pod Identity association."
  }
}

run "namespace_prefix" {
  command = plan
  variables { workload = { namespace = "payments-workers", service_account = "processor" } }
  assert {
    condition     = aws_eks_pod_identity_association.this[0].namespace == "payments-workers" && aws_eks_pod_identity_association.this[0].service_account == "processor"
    error_message = "Team-prefixed namespaces must be accepted and passed through."
  }
}

run "invalid_team" {
  command = plan
  variables {
    team = "BAD_TEAM"
    # Matching namespace, so only the team-name check fails.
    workload = { namespace = "BAD_TEAM", service_account = "app" }
  }
  expect_failures = [var.team]
}

run "invalid_environment" {
  command = plan
  variables { env = "qa" }
  expect_failures = [var.env]
}

run "missing_visibility" {
  command = plan
  variables { buckets = [{ name = "invoices" }] }
  expect_failures = [var.buckets]
}

run "missing_public_settings" {
  command = plan
  variables { buckets = [{ name = "invoices", visibility = "public" }] }
  expect_failures = [var.buckets]
}

run "private_forbids_public_settings" {
  command = plan
  variables { buckets = [{ name = "invoices", visibility = "private", public = { mode = "direct", justification = "Invalid" } }] }
  expect_failures = [var.buckets]
}

run "invalid_bucket_name" {
  command = plan
  variables { buckets = [{ name = "bad--name", visibility = "private" }] }
  expect_failures = [var.buckets]
}

run "duplicate_bucket_names" {
  command = plan
  variables {
    buckets = [{ name = "invoices", visibility = "private" }, { name = "invoices", visibility = "private" }]
  }
  expect_failures = [var.buckets]
}

run "no_active_buckets" {
  command = plan
  variables { buckets = [{ name = "invoices", visibility = "private", lifecycle = "decommission" }] }
  expect_failures = [var.buckets]
}

run "too_many_buckets" {
  command = plan
  variables { buckets = [for i in range(21) : { name = "bucket${i}", visibility = "private" }] }
  expect_failures = [var.buckets]
}

run "foreign_namespace" {
  command = plan
  variables { workload = { namespace = "paymentsother", service_account = "app" } }
  expect_failures = [var.workload]
}

run "invalid_lifecycle" {
  command = plan
  variables { lifecycle_state = "retained" }
  expect_failures = [var.lifecycle_state]
}
