#!/usr/bin/env bash
# Test against a real AWS sandbox account: checks that AWS really enforces the access
# rules, which the emulator can't. Not run yet (needs an account).
#
#   AWS_PROFILE=sandbox SANDBOX_ENV=dev tests/integration/run.sh
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
ENV=${SANDBOX_ENV:?set SANDBOX_ENV (an env whose envs/<env>.* point at the sandbox account)}
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
STATE_BUCKET="tfstate-$ENV-$ACCOUNT"
export TEAMS_DIR="$REPO/.out/integration/teams"
pass=0 fails=0
check() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; pass=$((pass+1)); else echo "  ✗ $1 (expected $2, got $3)"; fails=$((fails+1)); fi; }

for team in italpha itbeta; do
  mkdir -p "$TEAMS_DIR/$team"
  sed "s/__TEAM__/$team/g" "$REPO/tests/integration/team.yaml.tmpl" > "$TEAMS_DIR/$team/$ENV.yaml"
  "$REPO/scripts/tf.sh" init "$team" "$ENV" >/dev/null
  "$REPO/scripts/tf.sh" plan "$team" "$ENV" >/dev/null || [[ $? == 2 ]]
  "$REPO/scripts/tf.sh" apply "$team" "$ENV" >/dev/null
done

echo "Idempotency"
status=0; "$REPO/scripts/tf.sh" plan italpha "$ENV" >/dev/null || status=$?
check "second plan is empty" 0 "$status"

echo "Workload role isolation (IAM policy simulator, real evaluation incl. boundary)"
sim() { aws iam simulate-principal-policy --policy-source-arn "arn:aws:iam::$ACCOUNT:role/teams/$ENV-team-$1" \
  --action-names "$2" --resource-arns "$3" --query 'EvaluationResults[0].EvalDecision' --output text; }
check "italpha reads its bucket"   allowed       "$(sim italpha s3:GetObject "arn:aws:s3:::$ENV-italpha-data/x")"
check "italpha cannot read itbeta" implicitDeny  "$(sim italpha s3:GetObject "arn:aws:s3:::$ENV-itbeta-data/x")"

echo "Executor state isolation (real STS session tags)"
creds=$(aws sts assume-role --role-arn "arn:aws:iam::$ACCOUNT:role/tofu-apply-$ENV" --role-session-name it \
  --tags Key=team,Value=italpha --query Credentials --output json)
as_alpha() { AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$creds") AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$creds") \
  AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$creds") "$@"; }
check "executor(italpha) reads italpha state" 0 "$(as_alpha aws s3api head-object --bucket "$STATE_BUCKET" --key teams/italpha/terraform.tfstate >/dev/null 2>&1; echo $?)"
check "executor(italpha) cannot read itbeta state" 255 "$(as_alpha aws s3api head-object --bucket "$STATE_BUCKET" --key teams/itbeta/terraform.tfstate >/dev/null 2>&1; echo $?)"

echo "Anonymous access (real S3 + account Block Public Access)"
region=$(aws configure get region || echo eu-central-1)
echo ok | aws s3 cp - "s3://$ENV-italpha-public/probe.txt" >/dev/null
check "anonymous GET on direct-public bucket" 200 "$(curl -s -o /dev/null -w '%{http_code}' "https://$ENV-italpha-public.s3.$region.amazonaws.com/probe.txt")"
check "anonymous PUT on direct-public bucket" 403 "$(curl -s -o /dev/null -w '%{http_code}' -X PUT --data x "https://$ENV-italpha-public.s3.$region.amazonaws.com/probe2.txt")"
check "anonymous GET on private bucket"       403 "$(curl -s -o /dev/null -w '%{http_code}' "https://$ENV-italpha-data.s3.$region.amazonaws.com/x")"

echo "Cleanup through the real two-step flow: decommission (step 1), then offboard (step 2)"
for team in italpha itbeta; do
  f="$TEAMS_DIR/$team/$ENV.yaml"
  aws s3 rm "s3://$ENV-$team-public" --recursive >/dev/null 2>&1 || true
  sed -i.bak 's/^lifecycle: active/lifecycle: decommission/' "$f"
  "$REPO/scripts/tf.sh" plan "$team" "$ENV" >/dev/null || [[ $? == 2 ]]
  "$REPO/scripts/tf.sh" apply "$team" "$ENV" >/dev/null
  yq '.lifecycle = "decommission" | .buckets = []' "$f" > "$TEAMS_DIR/$team/offboard.yaml"
  export CONFIG_FILE="$TEAMS_DIR/$team/offboard.yaml"
  "$REPO/scripts/tf.sh" plan "$team" "$ENV" >/dev/null || [[ $? == 2 ]]
  "$REPO/scripts/tf.sh" apply "$team" "$ENV" >/dev/null
  "$REPO/scripts/tf.sh" forget-state "$team" "$ENV" >/dev/null
  unset CONFIG_FILE
done

echo "$pass passed, $fails failed"
(( fails == 0 ))
