# 10: even without the PR checks, the plan policy refuses to delete an active bucket.
s10() {
  local out status=0
  use_config alpha "$E2E_DIR/fixtures/alpha-drop-data.yaml"
  out=$(tf plan alpha 2>&1) || status=$?
  assert_eq 1 "$status" "plan is rejected"
  assert_contains "$out" 'bucket["data"].aws_s3_bucket.this would be deleted' "policy names the bucket it protects"
  assert_eq no "$([[ -f "$REPO/.out/local/alpha/plan.bin" ]] && echo yes || echo no)" "rejected plan was discarded"
  out=$(tf apply alpha 2>&1) || true
  assert_contains "$out" "missing saved plan" "apply refuses without an approved plan"
  assert_eq yes "$(bucket_exists "$(bucket alpha data)")" "bucket still exists"
  use_config alpha "$E2E_DIR/fixtures/alpha-decommission-public.yaml" # put it back
}
scenario 10 "Plan policy blocks unsafe deletes" s10
