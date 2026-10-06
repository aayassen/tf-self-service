#!/usr/bin/env bash
# Pull request rules. Prints one line per problem and fails if there is any.
#   usage: check.sh <base> <head>
#   Set PLATFORM_APPROVED=true when someone from the platform team approved.
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$REPO"
base=${1:?usage: check.sh <base> <head>} head=${2:?head commit}
report=$(mktemp); trap 'rm -f "$report"' EXIT
problem() { echo "✗ $1: $2" | tee -a "$report"; } # also works inside the piped loops below

# A file at a commit as JSON, or null if it didn't exist.
json_at() { git show "$1:$2" 2>/dev/null | yq -o=json '.' 2>/dev/null || echo null; }

changed=$(git diff --name-status --no-renames "$base" "$head")
team_changes=$(awk -F'\t' '$2 ~ /^teams\//' <<<"$changed")
other_changes=$(awk -F'\t' '$2 !~ /^teams\// { print $2 }' <<<"$changed")

# Team files must be teams/<team>/<env>.yaml
while IFS=$'\t' read -r status path; do
  [[ -n $path ]] || continue
  [[ $path =~ ^teams/([a-z][a-z0-9]{1,19})/(dev|staging|prod)\.yaml$ ]] \
    || problem "$path" "team files must be teams/<team>/<dev|staging|prod>.yaml; <team> is 2–20 lowercase letters/digits starting with a letter"
done <<<"$team_changes"

# One team per PR, and no platform code mixed in
teams=$(awk -F'\t' '{ split($2, p, "/"); print p[2] }' <<<"$team_changes" | sort -u | sed '/^$/d')
if (($(wc -l <<<"$teams") > 1)); then
  problem "PR" "changes more than one team ($(paste -sd, <<<"$teams")); open one PR per team"
fi
if [[ -n $teams && -n $other_changes ]]; then
  problem "PR" "mixes team files with platform code ($(head -3 <<<"$other_changes" | paste -sd, -)); split it"
fi

while IFS=$'\t' read -r status path; do
  [[ $path =~ ^teams/[^/]+/[^/]+\.yaml$ ]] || continue
  env=$(basename "$path" .yaml)
  before=$(json_at "$base" "$path")

  if [[ $status == D ]]; then
    # A team file can only be deleted after the team was decommissioned.
    [[ $(jq -r '.lifecycle // "active"' <<<"$before") == decommission ]] \
      || problem "$path" "deleted before the team was decommissioned; first merge 'lifecycle: decommission', then delete the file"
    continue
  fi

  # Schema check (also catches unknown fields and duplicate keys)
  if ! out=$(jsonschema validate schema/team.v1.schema.json "$path" 2>&1); then
    problem "$path" "does not match schema/team.v1.schema.json:"$'\n'"$(grep -E '^  [A-Z]|at instance location' <<<"$out" | head -8)"
    continue
  fi
  after=$(yq -o=json '.' "$path")

  # A bucket can only be removed after it was decommissioned.
  jq -r --argjson after "$after" '
      (.lifecycle // "active") as $team
      | .buckets // [] | .[]
      | select(.name as $n | [$after.buckets[].name] | index($n) | not)
      | select($team != "decommission" and (.lifecycle // "active") != "decommission")
      | .name' <<<"$before" | while read -r name; do
    problem "$path" "bucket '$name' removed while active; first merge 'lifecycle: decommission' on it, then remove it"
  done

  # New direct-public buckets in prod need platform approval.
  if [[ $env == prod && ${PLATFORM_APPROVED:-false} != true ]]; then
    jq -r --argjson before "$before" '
        [($before // {}).buckets // [] | .[] | select(.public.mode == "direct") | .name] as $old
        | .buckets[] | select(.public.mode == "direct" and (.lifecycle // "active") == "active")
        | select(.name as $n | $old | index($n) | not) | .name' <<<"$after" | while read -r name; do
      problem "$path" "bucket '$name' is directly public in prod; this needs an approving review from the platform team"
    done
  fi
done <<<"$team_changes"

[[ ! -s $report ]]
