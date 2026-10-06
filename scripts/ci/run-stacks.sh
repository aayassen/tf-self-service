#!/usr/bin/env bash
# Runs a batch of team stacks in one environment (one CI job).
#   usage: run-stacks.sh <plan|apply|drift> <env> "<team:action> <team:action> ..."
# action is "apply", or "destroy" when the team file was deleted.
# One failing team never stops the others; the job fails at the end.
# apply skips teams whose plan failed or had no changes.
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
mode=$1 env=$2 stacks=$3
failed=()
case $mode in plan|apply|drift) ;; *) echo "unknown mode: $mode" >&2; exit 1 ;; esac

# Switch to credentials that only work for this team (session tag team=<team>).
team_credentials() {
  [[ -n ${EXECUTOR_ROLE_ARN:-} ]] || return 0
  local creds
  creds=$(aws sts assume-role --role-arn "$EXECUTOR_ROLE_ARN" \
    --role-session-name "ci-$1-${GITHUB_RUN_ID:-local}" --tags "Key=team,Value=$1" \
    --query Credentials --output json) || return 1
  AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$creds")
  AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$creds")
  AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$creds")
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

# Show the team its role and bucket names in the run summary.
publish_outputs() {
  "$REPO/scripts/tf.sh" output "$1" "$env" 2>/dev/null | jq -r --arg t "$1" --arg e "$env" '
    "### \($e)/\($t)\n\nRole: `\(.role_arn.value // "none (team decommissioned)")`\n\n| bucket | S3 name | public URL |\n|---|---|---|",
    (.buckets.value // {} | to_entries[] | "| \(.key) | `\(.value.name)` | \(.value.public_url // "private") |"), ""' \
    >>"$GITHUB_STEP_SUMMARY" || true
}

# Runs in a subshell, so one team's credentials never leak to the next.
# set -e doesn't apply in here (it runs inside an if), hence the explicit returns.
run_stack() {
  local team=$1 action=$2 out="$REPO/.out/$env/$1" status=0
  mkdir -p "$out"
  export OUT_DIR=$out
  [[ $mode == apply ]] || rm -f "$out/no-changes" "$out/error.txt"
  if [[ $mode == apply && $action == apply ]]; then
    [[ -f $out/plan.bin ]] || { echo "skipped: no saved plan (the plan failed)"; return 0; }
    [[ ! -f $out/no-changes ]] || { echo "skipped: no changes"; return 0; }
  fi
  if [[ $action == destroy ]]; then
    # The file is gone: use its last version with no buckets left.
    export CONFIG_FILE="$out/offboard.yaml"
    git -C "$REPO" show "${BASE_SHA:?BASE_SHA is required for destroy}:teams/$team/$env.yaml" \
      | yq '.lifecycle = "decommission" | .buckets = []' >"$CONFIG_FILE" || return 1
  fi
  team_credentials "$team" || { echo "could not get credentials for $team" >"$out/error.txt"; return 1; }
  "$REPO/scripts/tf.sh" init "$team" "$env" >"$out/init.log" 2>&1 || { cp "$out/init.log" "$out/error.txt"; return 1; }
  case $mode in
    drift)
      "$REPO/scripts/tf.sh" plan "$team" "$env" >"$out/plan.log" 2>&1 || status=$?
      case $status in
        0) ;;
        2) echo "$team" >>"$REPO/.out/drift-$env-${MATRIX_ID:-1}.txt" ;;
        *) cp "$out/plan.log" "$out/error.txt"; return 1 ;;
      esac
      ;;
    plan)
      "$REPO/scripts/tf.sh" plan "$team" "$env" >"$out/plan.log" 2>&1 || status=$?
      if [[ $status != 0 && $status != 2 ]]; then cp "$out/plan.log" "$out/error.txt"; return 1; fi
      [[ $status == 2 ]] || touch "$out/no-changes"
      ;;
    apply)
      "$REPO/scripts/tf.sh" apply "$team" "$env" >"$out/apply.log" 2>&1 || { cp "$out/apply.log" "$out/error.txt"; return 1; }
      if [[ $action == destroy ]]; then
        "$REPO/scripts/tf.sh" forget-state "$team" "$env" >>"$out/apply.log" 2>&1 || { cp "$out/apply.log" "$out/error.txt"; return 1; }
      elif [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
        publish_outputs "$team"
      fi
      ;;
  esac
}

for item in $stacks; do
  team=${item%%:*} action=${item##*:}
  echo "::group::$env/$team ($action, $mode)"
  if (run_stack "$team" "$action"); then
    echo "✓ $env/$team"
  else
    echo "✗ $env/$team"; failed+=("$env/$team")
    [[ -f "$REPO/.out/$env/$team/error.txt" ]] && tail -30 "$REPO/.out/$env/$team/error.txt"
  fi
  echo "::endgroup::"
done

if ((${#failed[@]} > 0)); then
  echo "Failed: ${failed[*]} (see the errors above)" >&2
  exit 1
fi
