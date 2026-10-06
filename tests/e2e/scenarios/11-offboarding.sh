# 11: removing decommissioned buckets deletes the empty ones and keeps the ones with data.
# Deleting a team file does the same, then removes the team's state.
s11() {
  local pub reports beta status=0
  pub=$(bucket alpha public) reports=$(bucket alpha reports) beta=$(bucket beta data)

  use_config alpha "$E2E_DIR/fixtures/alpha-decommission-both.yaml"; converge alpha
  use_config alpha "$E2E_DIR/fixtures/alpha-offboarded-buckets.yaml"
  status=$(plan_exit alpha)
  assert_eq 2 "$status" "removing decommissioned entries plans changes"
  assert_eq "public $pub" "$(cat "$REPO/.out/local/alpha/retain.txt")" "only the non-empty bucket is marked for retention"
  assert_contains "$(summary)" '📦 retain bucket `public`' "PR summary: non-empty bucket shown as retained"
  assert_contains "$(summary)" '➖ delete bucket `reports`' "PR summary: empty bucket shown as deleted"
  tf apply alpha >"$E2E_OUT/logs/apply-alpha-offboard.log" 2>&1 || fail "apply failed (see logs/apply-alpha-offboard.log)"
  assert_eq no  "$(bucket_exists "$reports")" "empty decommissioned bucket deleted"
  assert_eq yes "$(bucket_exists "$pub")" "non-empty bucket retained"
  assert_eq "keep me" "$(aws s3 cp "s3://$pub/precious.txt" - 2>/dev/null)" "retained data intact"
  assert_eq retained "$(bucket_tag "$pub" platform:lifecycle)" "retained bucket tagged platform:lifecycle=retained"
  assert_eq '[true,true,true,true]' "$(pab "$pub")" "retained bucket stays private"
  assert_eq 0 "$(tf show alpha | jq --arg b "$pub" '[.. | strings | select(. == $b)] | length')" "retained bucket no longer in alpha's state"
  assert_eq 0 "$(plan_exit alpha)" "alpha converged (idempotent after offboarding)"

  # Delete beta's file (decommissioned in scenario 08).
  rm -r "$TEAMS_DIR/beta"
  ( export CONFIG_FILE="$E2E_DIR/fixtures/beta-deleted.yaml"
    status=0; tf plan beta || status=$?
    [[ $status == 2 ]] && tf apply beta && tf forget-state beta
  ) >"$E2E_OUT/logs/offboard-beta.log" 2>&1 || fail "team offboarding failed (see logs/offboard-beta.log)"
  assert_eq no "$(bucket_exists "$beta")" "beta's empty bucket deleted"
  assert_eq 0 "$(aws s3api list-objects-v2 --bucket tfstate-local --prefix teams/beta/ --query 'length(Contents || `[]`)' --output text)" \
    "beta's state object removed"
}
scenario 11 "Offboarding step 2 (delete empty, retain non-empty)" s11
