# 01: onboarding two teams creates secure buckets and a tightly scoped role.
s01() {
  converge alpha && converge beta || return
  assert_contains "$(summary)" '➕ create bucket `public` (⚠️ public: direct)' "PR summary flags the new public bucket"

  assert_eq yes "$(bucket_exists "$(bucket alpha data)")"   "alpha private bucket exists"
  assert_eq yes "$(bucket_exists "$(bucket alpha public)")" "alpha public bucket exists"
  assert_eq yes "$(bucket_exists "$(bucket beta data)")"    "beta private bucket exists"

  assert_eq '[true,true,true,true]'   "$(pab "$(bucket alpha data)")"   "private bucket: all four Block Public Access flags on"
  assert_eq '[true,true,false,false]' "$(pab "$(bucket alpha public)")" "direct-public bucket: ACL blocks on, policy blocks off"
  assert_eq 'DenyInsecureTransport'   "$(policy_sids "$(bucket alpha data)")" "private bucket policy: TLS deny only"
  assert_eq 'DenyInsecureTransport,PublicReadObjects' "$(policy_sids "$(bucket alpha public)")" "public bucket policy: TLS deny + public read"
  assert_eq '["s3:GetObject"]' \
    "$(aws s3api get-bucket-policy --bucket "$(bucket alpha public)" --query Policy --output text | jq -c '[.Statement[] | select(.Sid=="PublicReadObjects") | .Action] | flatten')" \
    "public statement grants s3:GetObject only"
  assert_eq Enabled "$(aws s3api get-bucket-versioning --bucket "$(bucket alpha data)" --query Status --output text)" "versioning enabled"
  assert_eq AES256 "$(aws s3api get-bucket-encryption --bucket "$(bucket alpha data)" \
    --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)" "SSE-S3 encryption"

  local r; r=$(aws iam get-role --role-name "$(role alpha)" --output json)
  assert_eq /teams/ "$(jq -r .Role.Path <<<"$r")" "role lives under /teams/"
  assert_eq "arn:aws:iam::123456789012:policy/platform/team-boundary" \
    "$(jq -r .Role.PermissionsBoundary.PermissionsBoundaryArn <<<"$r")" "role has the platform permissions boundary"
  assert_eq "arn:aws:s3:::local-alpha-data,arn:aws:s3:::local-alpha-public" \
    "$(role_policy_resources "$(role alpha)")" "role policy lists exactly alpha's bucket ARNs"
}
scenario 01 "Onboard two teams" s01
