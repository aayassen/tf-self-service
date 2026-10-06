# 09: a bucket without visibility is rejected before anything changes.
s09() {
  local before after out status=0
  before=$(aws s3api head-object --bucket tfstate-local --key teams/alpha/terraform.tfstate --query ETag --output text)
  use_config alpha "$E2E_DIR/fixtures/alpha-missing-visibility.yaml"
  out=$(tf plan alpha 2>&1) || status=$?
  assert_eq 1 "$status" "plan fails"
  assert_contains "$out" "requires visibility" "error explains that visibility is required"
  after=$(aws s3api head-object --bucket tfstate-local --key teams/alpha/terraform.tfstate --query ETag --output text)
  assert_eq "$before" "$after" "state unchanged"
}
scenario 09 "Guard rail: missing visibility" s09
