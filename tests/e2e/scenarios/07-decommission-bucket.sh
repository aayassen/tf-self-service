# 07: decommissioning a bucket makes it private and removes access; the data stays.
s07() {
  local b; b=$(bucket alpha public)
  echo "keep me" | aws s3 cp - "s3://$b/precious.txt" >/dev/null
  use_config alpha "$E2E_DIR/fixtures/alpha-decommission-public.yaml"; converge alpha
  assert_eq yes "$(bucket_exists "$b")" "bucket still exists"
  assert_eq "keep me" "$(aws s3 cp "s3://$b/precious.txt" - 2>/dev/null)" "data untouched"
  assert_eq '[true,true,true,true]' "$(pab "$b")" "decommissioned bucket is fully private"
  assert_eq DenyInsecureTransport "$(policy_sids "$b")" "public statement removed"
  assert_eq decommission "$(bucket_tag "$b" platform:lifecycle)" "bucket tagged platform:lifecycle=decommission"
  assert_eq "arn:aws:s3:::local-alpha-data,arn:aws:s3:::local-alpha-reports" \
    "$(role_policy_resources "$(role alpha)")" "bucket removed from the team role policy"
}
scenario 07 "Decommission a bucket (step 1)" s07
