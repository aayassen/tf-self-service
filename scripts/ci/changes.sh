#!/usr/bin/env bash
# Lists the team stacks a change affects, as a GitHub Actions matrix.
#   changes.sh <base> <head> [env...]
#   changes.sh --all [env...]
# A changed team file means that team; a platform change means every team.
# Teams are grouped into jobs of BATCH_SIZE (default 25).
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$REPO"

ENVS=(dev staging prod)
PLATFORM_PATHS=(modules stacks envs policy scripts/tf.sh)
batch=${BATCH_SIZE:-25}

all_stacks() {
  local f
  for f in teams/*/*.yaml; do
    [[ -f $f ]] || continue
    f=${f#teams/}
    echo "${f#*/}" "${f%%/*}" apply
  done | sed 's/\.yaml / /'
}

if [[ ${1:-} == --all ]]; then
  shift
  stacks=$(all_stacks)
else
  base=${1:?usage: changes.sh <base> <head> [env...] | --all [env...]} head=${2:?head commit}
  shift 2
  diff=$(git diff --name-status --no-renames "$base" "$head")
  stacks=$(awk -F'\t' '$2 ~ /^teams\/[^\/]+\/[^\/]+\.yaml$/ {
      split($2, p, "/"); sub(/\.yaml$/, "", p[3])
      print p[3], p[2], ($1 == "D" ? "destroy" : "apply") }' <<<"$diff")
  if git diff --quiet "$base" "$head" -- "${PLATFORM_PATHS[@]}"; then :; else
    stacks=$( { all_stacks; grep ' destroy$' <<<"$stacks" || true; } )
  fi
fi
(($# > 0)) && ENVS=("$@")

printf '%s\n' "$stacks" | awk -v envs="${ENVS[*]}" 'BEGIN { n = split(envs, e, " "); for (i = 1; i <= n; i++) ok[e[i]] = 1 }
  NF == 3 && ok[$1]' | sort -u | jq -Rnc --argjson size "$batch" '
  [inputs | split(" ") | {env: .[0], stack: "\(.[1]):\(.[2])"}]
  | group_by(.env)
  | map(. as $g | [range(0; length; $size) as $i | $g[$i:$i + $size]])
  | [.[][] | {env: .[0].env, stacks: (map(.stack) | join(" ")), count: length}]
  | to_entries | map(.value + {id: "\(.value.env)-\(.key + 1)"})
  | {include: .}'
