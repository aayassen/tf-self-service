# Helpers for the e2e scenarios.

E2E_FAILURES=0
E2E_RESULTS=()

log()  { printf '    %s\n' "$*"; }
die()  { printf 'e2e: %s\n' "$*" >&2; exit 1; }

fail() { printf '    ✗ %s\n' "$*"; SCENARIO_OK=false; }
ok()   { printf '    ✓ %s\n' "$*"; }

assert_eq() { # <expected> <actual> <message>
  if [[ "$1" == "$2" ]]; then ok "$3"; else fail "$3 (expected '$1', got '$2')"; fi
}

assert_contains() { # <text> <expected part> <message>
  if [[ "$1" == *"$2"* ]]; then ok "$3"; else fail "$3 (missing '$2')"; fi
}

# scenario <id> <title> <function>
scenario() {
  local id=$1 title=$2 fn=$3
  printf '\n[%s] %s\n' "$id" "$title"
  SCENARIO_OK=true
  # One broken scenario doesn't stop the rest.
  "$fn" || SCENARIO_OK=false
  if $SCENARIO_OK; then
    E2E_RESULTS+=("PASS  $id $title")
  else
    E2E_RESULTS+=("FAIL  $id $title"); E2E_FAILURES=$((E2E_FAILURES + 1))
  fi
}


tf() { "$REPO/scripts/tf.sh" "$@" local; } # tf <action> <team>

# Swap a team's file for one of the fixtures.
use_config() { cp "$2" "$TEAMS_DIR/$1/local.yaml"; }

# Prints 0 (no changes), 2 (changes) or 1 (error).
plan_exit() {
  local status=0
  tf plan "$1" >"$E2E_OUT/logs/plan-$1.log" 2>&1 || status=$?
  echo "$status"
}

# init + plan + apply.
converge() {
  tf init "$1" >"$E2E_OUT/logs/init-$1.log" 2>&1 || { fail "init $1 failed (see logs/init-$1.log)"; return 1; }
  local status; status=$(plan_exit "$1")
  case $status in
    0) return 0 ;;
    2) tf apply "$1" >"$E2E_OUT/logs/apply-$1.log" 2>&1 || { fail "apply $1 failed (see logs/apply-$1.log)"; return 1; } ;;
    *) fail "plan $1 failed (see logs/plan-$1.log)"; return 1 ;;
  esac
}

plan_json() { echo "$REPO/.out/local/$1/plan.json"; }
summary()   { "$REPO/scripts/ci/summarize.sh" "$REPO/.out"; } # the PR comment

# Lookups in the emulator

bucket()       { echo "local-$1-$2"; }  # bucket <team> <name>
role()         { echo "local-team-$1"; }
pab()          { aws s3api get-public-access-block --bucket "$1" --query 'PublicAccessBlockConfiguration' --output json | jq -c '[.BlockPublicAcls,.IgnorePublicAcls,.BlockPublicPolicy,.RestrictPublicBuckets]'; }
policy_sids()  { aws s3api get-bucket-policy --bucket "$1" --query Policy --output text | jq -r '[.Statement[].Sid] | sort | join(",")'; }
bucket_tag()   { aws s3api get-bucket-tagging --bucket "$1" --output json | jq -r --arg k "$2" '.TagSet[] | select(.Key == $k) | .Value'; }
bucket_exists(){ aws s3api head-bucket --bucket "$1" >/dev/null 2>&1 && echo yes || echo no; }
role_exists()  { aws iam get-role --role-name "$1" >/dev/null 2>&1 && echo yes || echo no; }
role_policy_resources() { # buckets listed in the team role's policy
  aws iam get-role-policy --role-name "$1" --policy-name active-buckets --query PolicyDocument --output json \
    | jq -r '.Statement[0].Resource | if type == "string" then [.] else . end | sort | join(",")'
}
