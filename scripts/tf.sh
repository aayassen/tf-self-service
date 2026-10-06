#!/usr/bin/env bash
# Runs OpenTofu for one team in one environment, with that team's own state.
#
#   tf.sh <init|plan|apply|forget-state|output|show> <team> <env>
#
#   plan          exits 0 for no changes, 2 for changes (read-only, no lock)
#   apply         applies the saved plan only
#   forget-state  deletes the team's state once it is empty
#
# Optional: CONFIG_FILE overrides teams/<team>/<env>.yaml.
set -euo pipefail

fail() { echo "tf.sh: $*" >&2; exit 1; }
[[ $# == 3 ]] || fail "usage: tf.sh <init|plan|apply|forget-state|output|show> <team> <env>"
action=$1 team=$2 env=$3
case "$action" in init|plan|apply|forget-state|output|show) ;; *) fail "unknown command: $action" ;; esac
[[ $team =~ ^[a-z][a-z0-9]{1,19}$ ]] || fail "invalid team '$team': use 2–20 lowercase letters/digits, starting with a letter"
case "$env" in dev|staging|prod|local) ;; *) fail "invalid env '$env': use dev, staging, prod or local" ;; esac

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v conftest >/dev/null || fail "conftest is required for plan policy checks (run: mise install)"
config=${CONFIG_FILE:-${TEAMS_DIR:-$REPO/teams}/$team/$env.yaml}
[[ -f $config ]] || fail "missing team config: $config"
config=$(cd -- "$(dirname -- "$config")" && printf '%s/%s' "$PWD" "$(basename -- "$config")")
export TF_DATA_DIR="${TF_DATA_ROOT:-$REPO/.tfdata}/$env/$team"
OUT_DIR=${OUT_DIR:-$REPO/.out/$env/$team}
mkdir -p -- "$TF_DATA_DIR" "$OUT_DIR"
TF_DATA_DIR=$(cd -- "$TF_DATA_DIR" && pwd)
OUT_DIR=$(cd -- "$OUT_DIR" && pwd)
if [[ -n ${TF_PLUGIN_CACHE_DIR:-} ]]; then
  mkdir -p -- "$TF_PLUGIN_CACHE_DIR"
  export TF_PLUGIN_CACHE_DIR
  TF_PLUGIN_CACHE_DIR=$(cd -- "$TF_PLUGIN_CACHE_DIR" && pwd)
fi
export TF_INPUT=0
lock_timeout=${TF_LOCK_TIMEOUT:-10m}
tofu_cmd=(tofu "-chdir=$REPO/stacks/team")
vars=("-var-file=$REPO/envs/$env.tfvars" "-var=team=$team" "-var=env=$env" "-var=config_file=$config")
backend_file="$REPO/envs/$env.backend.hcl"
state_key="teams/$team/terraform.tfstate"
retain_file="$OUT_DIR/retain.txt"

# Old versions and delete markers count as data too.
bucket_has_data() {
  local n
  n=$(aws s3api list-object-versions --bucket "$1" --max-items 1 \
    --query 'length([Versions[0], DeleteMarkers[0]][])' --output text)
  [[ $n != 0 ]]
}

tag_retained() {
  local tags
  tags=$(aws s3api get-bucket-tagging --bucket "$1" --output json 2>/dev/null || echo '{"TagSet":[]}')
  tags=$(jq -c '{TagSet: ([.TagSet[] | select(.Key != "platform:lifecycle")] + [{Key: "platform:lifecycle", Value: "retained"}])}' <<<"$tags")
  aws s3api put-bucket-tagging --bucket "$1" --tagging "$tags"
}

case "$action" in
  init)
    "${tofu_cmd[@]}" init -input=false -reconfigure "-lock-timeout=$lock_timeout" \
      "-backend-config=$backend_file" \
      "-backend-config=key=$state_key"
    ;;
  plan)
    status=0
    "${tofu_cmd[@]}" plan -input=false "-lock=false" "-lock-timeout=$lock_timeout" \
      -detailed-exitcode "-out=$OUT_DIR/plan.bin" "${vars[@]}" || status=$?
    [[ $status == 0 || $status == 2 ]] || exit "$status"
    "${tofu_cmd[@]}" show -json "$OUT_DIR/plan.bin" > "$OUT_DIR/plan.json"
    # A plan that breaks the policy is deleted, so it can never be applied.
    if ! conftest test --no-color --policy "$REPO/policy" "$OUT_DIR/plan.json"; then
      rm -f -- "$OUT_DIR/plan.bin"
      fail "plan rejected by platform policy (see above); nothing will be applied"
    fi
    # Buckets about to be deleted that still hold data are kept instead (see apply).
    : > "$retain_file"
    jq -r '.resource_changes[] | select(.type == "aws_s3_bucket" and .change.actions == ["delete"])
           | [(.address | capture("bucket\\[\"(?<k>[^\"]+)\"\\]").k), .change.before.bucket] | @tsv' \
      "$OUT_DIR/plan.json" | while IFS=$'\t' read -r key name; do
      if bucket_has_data "$name"; then
        echo "$key $name" >> "$retain_file"
        echo "tf.sh: bucket $name is not empty; it will be RETAINED (forgotten by OpenTofu, kept private, tagged platform:lifecycle=retained)" >&2
      fi
    done
    exit "$status"
    ;;
  apply)
    [[ -f $OUT_DIR/plan.bin ]] || fail "missing saved plan: $OUT_DIR/plan.bin; run plan first"
    if [[ -s $retain_file ]]; then
      # Keep non-empty buckets: tag them, drop them from state, then plan again.
      while read -r key name; do
        tag_retained "$name"
        "${tofu_cmd[@]}" state rm "-lock-timeout=$lock_timeout" "module.team.module.bucket[\"$key\"]"
      done < "$retain_file"
      status=0
      "$0" plan "$team" "$env" || status=$?
      [[ $status == 0 || $status == 2 ]] || exit "$status"
    fi
    "${tofu_cmd[@]}" apply -input=false "-lock-timeout=$lock_timeout" "$OUT_DIR/plan.bin"
    ;;
  forget-state)
    # Only allowed once the state manages nothing (data sources don't count).
    managed=$("${tofu_cmd[@]}" state list | grep -Ev '(^|\.)data\.' || true)
    [[ -z $managed ]] || fail "state for $team/$env still manages resources; not deleting it:"$'\n'"$managed"
    bucket=$(sed -n 's/^bucket[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' "$backend_file")
    aws s3 rm "s3://$bucket/$state_key"
    ;;
  output)
    "${tofu_cmd[@]}" output -json
    ;;
  show)
    "${tofu_cmd[@]}" show -json
    ;;
esac
