output "role_arn" {
  value = module.team.role_arn
}

output "role_name" {
  value = module.team.role_name
}

output "buckets" {
  value = module.team.buckets
}

# Used by the plan policy: the role may only be deleted when the team is decommissioning.
output "team_lifecycle" {
  value = local.lifecycle
}
