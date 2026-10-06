# 02: every team has its own state file with only its own resources.
s02() {
  assert_eq "teams/alpha/terraform.tfstate,teams/beta/terraform.tfstate" \
    "$(aws s3api list-objects-v2 --bucket tfstate-local --prefix teams/ --query 'Contents[].Key' --output json | jq -r 'sort | join(",")')" \
    "exactly one state object per team (no leftover .tflock)"
  local team other
  for team in alpha beta; do
    other=$([[ $team == alpha ]] && echo beta || echo alpha)
    aws s3 cp "s3://tfstate-local/teams/$team/terraform.tfstate" "$E2E_OUT/$team.tfstate" >/dev/null
    assert_eq 0 "$(jq --arg o "$other" '[.. | strings | select(contains("local-" + $o + "-") or contains("team-" + $o))] | length' "$E2E_OUT/$team.tfstate")" \
      "$team state references none of $other's resources"
  done
}
scenario 02 "Per-team state isolation (layout)" s02
