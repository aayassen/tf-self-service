# 08: decommissioning a team removes its role; the buckets and data stay.
s08() {
  use_config beta "$E2E_DIR/fixtures/beta-decommission.yaml"; converge beta
  assert_eq no  "$(role_exists "$(role beta)")" "beta role deleted"
  assert_eq yes "$(bucket_exists "$(bucket beta data)")" "beta bucket retained"
  assert_eq decommission "$(bucket_tag "$(bucket beta data)" platform:lifecycle)" "beta bucket tagged decommission"
  assert_eq yes "$(role_exists "$(role alpha)")" "alpha unaffected"
}
scenario 08 "Decommission a team (step 1)" s08
