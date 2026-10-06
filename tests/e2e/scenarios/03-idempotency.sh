# 03: right after an apply, a new plan shows no changes.
s03() {
  local team
  for team in alpha beta; do
    assert_eq 0 "$(plan_exit "$team")" "$team plan is empty after apply (idempotent)"
  done
  assert_eq alpha    "$(bucket_tag "$(bucket alpha data)" platform:team)"        "bucket tagged platform:team"
  assert_eq CC-0001  "$(bucket_tag "$(bucket alpha data)" platform:cost-center)" "bucket tagged platform:cost-center"
  assert_eq teams/alpha/local.yaml "$(bucket_tag "$(bucket alpha data)" platform:source)" "bucket tagged with its source file"
}
scenario 03 "Idempotent re-apply" s03
