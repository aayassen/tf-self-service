mock_provider "aws" {
  # Must look like a real ARN, even with mocks.
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/teams/mock" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_region" {
    defaults = { region = "eu-central-1" }
  }
}
variables {
  region                   = "eu-central-1"
  cluster_name             = "dev"
  permissions_boundary_arn = "arn:aws:iam::111111111111:policy/platform/team-boundary"
  team                     = "payments"
  env                      = "dev"
}

run "valid_minimal_private" {
  command = plan
  variables {
    config_file = "../../tests/fixtures/valid/minimal-private.yaml"
    team        = "payments"
    env         = "dev"
  }
  assert {
    condition = (
      output.role_name == "dev-team-payments" &&
      toset(keys(output.buckets)) == toset(["invoices"]) &&
      alltrue([for name, bucket in output.buckets : bucket.name == "dev-payments-${name}"]) &&
      alltrue([for bucket in output.buckets : bucket.visibility == "private" && bucket.public_url == null])
    )
    error_message = "valid_minimal_private: YAML must flow through the real root with exact names, lifecycle and visibility."
  }
}

run "valid_mixed" {
  command = plan
  variables {
    config_file = "../../tests/fixtures/valid/mixed.yaml"
    team        = "payments"
    env         = "dev"
  }
  assert {
    condition = (
      output.role_name == "dev-team-payments" &&
      toset(keys(output.buckets)) == toset(["invoices", "web-assets", "integration-downloads"]) &&
      alltrue([for name, bucket in output.buckets : bucket.name == "dev-payments-${name}"]) &&
      output.buckets["invoices"].visibility == "private" && output.buckets["web-assets"].visibility == "public" && output.buckets["integration-downloads"].visibility == "public"
    )
    error_message = "valid_mixed: YAML must flow through the real root with exact names, lifecycle and visibility."
  }
}

run "valid_bucket_decommission" {
  command = plan
  variables {
    config_file = "../../tests/fixtures/valid/bucket-decommission.yaml"
    team        = "payments"
    env         = "dev"
  }
  assert {
    condition = (
      output.role_name == "dev-team-payments" &&
      toset(keys(output.buckets)) == toset(["invoices", "web-assets", "integration-downloads"]) &&
      alltrue([for name, bucket in output.buckets : bucket.name == "dev-payments-${name}"]) &&
      output.buckets["web-assets"].visibility == "private" && output.buckets["web-assets"].public_url == null && output.buckets["integration-downloads"].visibility == "private" && output.buckets["integration-downloads"].public_url == null
    )
    error_message = "valid_bucket_decommission: YAML must flow through the real root with exact names, lifecycle and visibility."
  }
}

run "valid_team_decommission" {
  command = plan
  variables {
    config_file = "../../tests/fixtures/valid/team-decommission.yaml"
    team        = "payments"
    env         = "dev"
  }
  assert {
    condition = (
      output.role_name == null && output.role_arn == null &&
      toset(keys(output.buckets)) == toset(["invoices", "web-assets", "integration-downloads"]) &&
      alltrue([for name, bucket in output.buckets : bucket.name == "dev-payments-${name}"]) &&
      alltrue([for bucket in output.buckets : bucket.visibility == "private" && bucket.public_url == null])
    )
    error_message = "valid_team_decommission: YAML must flow through the real root with exact names, lifecycle and visibility."
  }
}

run "payments_dev" {
  command = plan
  variables {
    config_file = "../../teams/payments/dev.yaml"
    team        = "payments"
    env         = "dev"
  }
  assert {
    condition = (
      output.role_name == "dev-team-payments" &&
      toset(keys(output.buckets)) == toset(["invoices", "web-assets", "integration-downloads"]) &&
      alltrue([for name, bucket in output.buckets : bucket.name == "dev-payments-${name}"]) &&
      output.buckets["invoices"].visibility == "private" && output.buckets["web-assets"].visibility == "public" && output.buckets["integration-downloads"].visibility == "public"
    )
    error_message = "payments_dev: YAML must flow through the real root with exact names, lifecycle and visibility."
  }
}

run "payments_staging" {
  command = plan
  variables {
    config_file = "../../teams/payments/staging.yaml"
    team        = "payments"
    env         = "staging"
  }
  assert {
    condition = (
      output.role_name == "staging-team-payments" &&
      toset(keys(output.buckets)) == toset(["invoices", "web-assets"]) &&
      alltrue([for name, bucket in output.buckets : bucket.name == "staging-payments-${name}"]) &&
      output.buckets["invoices"].visibility == "private" && output.buckets["web-assets"].visibility == "public"
    )
    error_message = "payments_staging: YAML must flow through the real root with exact names, lifecycle and visibility."
  }
}

run "payments_prod" {
  command = plan
  variables {
    config_file = "../../teams/payments/prod.yaml"
    team        = "payments"
    env         = "prod"
  }
  assert {
    condition = (
      output.role_name == "prod-team-payments" &&
      toset(keys(output.buckets)) == toset(["invoices", "web-assets"]) &&
      alltrue([for name, bucket in output.buckets : bucket.name == "prod-payments-${name}"]) &&
      output.buckets["invoices"].visibility == "private" && output.buckets["web-assets"].visibility == "public"
    )
    error_message = "payments_prod: YAML must flow through the real root with exact names, lifecycle and visibility."
  }
}

run "invalid_visibility" {
  command = plan
  variables {
    config_file = "../../tests/fixtures/invalid/invalid-visibility.yaml"
  }
  expect_failures = [var.config_file]
}

run "missing_visibility" {
  command = plan
  variables {
    config_file = "../../tests/fixtures/invalid/missing-visibility.yaml"
  }
  expect_failures = [var.config_file]
}

run "blank_justification" {
  command = plan
  variables {
    config_file = "../../tests/fixtures/invalid/blank-justification.yaml"
  }
  expect_failures = [var.config_file]
}

run "invalid_mode" {
  command = plan
  variables {
    config_file = "../../tests/fixtures/invalid/invalid-mode.yaml"
  }
  expect_failures = [var.config_file]
}

run "missing_public" {
  command = plan
  variables {
    config_file = "../../tests/fixtures/invalid/missing-public.yaml"
  }
  expect_failures = [var.config_file]
}

run "private_public_settings" {
  command = plan
  variables {
    config_file = "../../tests/fixtures/invalid/private-public-settings.yaml"
  }
  expect_failures = [var.config_file]
}

run "double_hyphen" {
  command = plan
  variables {
    config_file = "../../tests/fixtures/invalid/double-hyphen.yaml"
  }
  expect_failures = [var.config_file]
}

run "duplicate_name" {
  command = plan
  variables {
    config_file = "../../tests/fixtures/invalid/duplicate-name.yaml"
  }
  expect_failures = [var.config_file]
}

run "no_active_buckets" {
  command = plan
  variables {
    config_file = "../../tests/fixtures/invalid/no-active-buckets.yaml"
  }
  expect_failures = [var.config_file]
}

run "too_many_buckets" {
  command = plan
  variables {
    config_file = "../../tests/fixtures/invalid/too-many-buckets.yaml"
  }
  expect_failures = [var.config_file]
}

run "foreign_namespace" {
  command = plan
  variables {
    config_file = "../../tests/fixtures/invalid/foreign-namespace.yaml"
  }
  expect_failures = [var.config_file]
}
