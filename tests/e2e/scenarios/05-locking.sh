# 05: a lock on one team's state blocks that team only, until it is released.
s05() {
  local lock=teams/alpha/terraform.tfstate.tflock out status=0
  assert_eq 0 "$(plan_exit alpha)" "alpha has a saved plan"
  printf '{"ID":"e2e-held-lock","Operation":"OperationTypeApply","Who":"e2e@scenario05","Version":"1.13.1","Path":"tfstate-local/teams/alpha/terraform.tfstate"}' \
    | aws s3 cp - "s3://tfstate-local/$lock" >/dev/null
  out=$(TF_LOCK_TIMEOUT=0s "$REPO/scripts/tf.sh" apply alpha local 2>&1) || status=$?
  assert_eq 1 "$status" "apply fails while another run holds the lock"
  assert_contains "$out" "Error acquiring the state lock" "error names the state lock"
  assert_contains "$out" "e2e-held-lock" "error shows who holds the lock"
  assert_eq 0 "$(plan_exit beta)" "beta still plans"
  tf apply beta >"$E2E_OUT/logs/apply-beta-05.log" 2>&1 && ok "beta is not blocked by alpha's lock" || fail "beta apply was blocked"
  aws s3 rm "s3://tfstate-local/$lock" >/dev/null
  tf apply alpha >"$E2E_OUT/logs/apply-alpha-05.log" 2>&1 && ok "alpha applies once the lock is released" || fail "alpha apply failed after release"
}
scenario 05 "Native S3 state locking" s05
