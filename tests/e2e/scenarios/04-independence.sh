# 04: changing one team's file only changes that team.
s04() {
  use_config alpha "$E2E_DIR/fixtures/alpha-extra.yaml"
  assert_eq 2 "$(plan_exit alpha)" "alpha plan has changes after adding a bucket"
  assert_eq true "$(jq '[.resource_changes[] | select(.change.actions == ["create"]) | .address] | any(contains("bucket[\"reports\"]"))' "$(plan_json alpha)")" \
    "alpha plan creates the new 'reports' bucket"
  assert_eq 0 "$(jq '[.resource_changes[] | select(.change.actions | index("delete"))] | length' "$(plan_json alpha)")" \
    "adding a bucket destroys/replaces nothing (stable for_each keys)"
  assert_eq 0 "$(plan_exit beta)" "beta plan is untouched"
  assert_contains "$(summary)" '| local | alpha | ➕ create bucket `reports`' "PR summary: alpha creates 'reports'"
  assert_contains "$(summary)" '1 team stack(s) with no changes' "PR summary: beta has no changes"
  summary >"$E2E_OUT/logs/summary-04.md"
  tf apply alpha >"$E2E_OUT/logs/apply-alpha-extra.log" 2>&1 || fail "alpha apply failed"
  converge alpha # the emulator needs a second pass for tags
  assert_eq "arn:aws:s3:::local-alpha-data,arn:aws:s3:::local-alpha-public,arn:aws:s3:::local-alpha-reports" \
    "$(role_policy_resources "$(role alpha)")" "role policy now includes the new bucket"
}
scenario 04 "Team independence" s04
