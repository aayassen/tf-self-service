#!/usr/bin/env bash
# Writes the PR comment from the plan results.
#   usage: summarize.sh <results-dir> [check-output]
set -euo pipefail
dir=${1:?usage: summarize.sh <results-dir> [findings-file]} findings=${2:-}

# One line per changed bucket or role, e.g. "➕ create bucket `invoices`".
changes() {
  local retained='[]'
  [[ -s $2 ]] && retained=$(awk '{ print $1 }' "$2" | jq -Rnc '[inputs]')
  jq -r --argjson retained "$retained" '
    def verb: if index("create") and index("delete") then "♻️ replace"
              elif index("create") then "➕ create" elif index("delete") then "➖ delete"
              else "✏️ update" end;
    [.resource_changes[] | select(.change.actions != ["no-op"] and .change.actions != ["read"])
      | . + {bucket: (.address | capture("module\\.bucket\\[\"(?<k>[^\"]+)\"\\]").k? // null)}] as $rc
    | ($rc | map(select(.bucket)) | group_by(.bucket)[] | . as $g | $g[0].bucket as $b
        | ([$g[] | select(.type == "aws_s3_bucket") | .change.actions[]] | unique) as $main
        | (if ($main | index("delete")) and ($retained | index($b)) then "📦 retain"
           elif ($main | length) > 0 then $main | verb else "✏️ update" end) as $v
        | ([$g[] | select(.change.actions | index("create") or index("update"))
             | select(.type == "aws_cloudfront_distribution"
                      or (.type == "aws_s3_bucket_public_access_block" and .change.after.restrict_public_buckets == false))
             | if .type == "aws_cloudfront_distribution" then "cloudfront" else "direct" end] | unique) as $pub
        | "\($v) bucket `\($b)`" + (if ($pub | length) > 0 then " (⚠️ public: \($pub | join(", ")))" else "" end)),
      ($rc | map(select(.bucket == null and (.type | startswith("aws_iam") or startswith("aws_eks"))))
        | select(length > 0) | "\([.[].change.actions[]] | unique | verb) team role / access")
  ' "$1"
}

echo '<!-- platform-plan -->'
echo '## Infrastructure plan'
echo
if [[ -s $findings ]]; then
  echo '### ❌ Checks failed'
  echo
  echo '```'
  cat "$findings"
  echo '```'
  echo
fi

rows=() details=() public=false failed=false retained=false
for stack in "$dir"/*/*/; do
  [[ -d $stack ]] || continue
  env=$(basename "$(dirname "$stack")") team=$(basename "$stack")
  if [[ -f $stack/error.txt ]]; then
    failed=true
    rows+=("| $env | $team | ❌ failed, see below |")
    details+=("<details><summary>$env/$team error</summary>" "" '```' "$(tail -40 "$stack/error.txt")" '```' "</details>")
  elif [[ -f $stack/plan.json ]]; then
    lines=$(changes "$stack/plan.json" "$stack/retain.txt")
    [[ $lines == *"⚠️ public"* ]] && public=true
    [[ $lines == *"📦 retain"* ]] && retained=true
    rows+=("| $env | $team | ${lines:-no changes} |")
  fi
done
rows=("${rows[@]//$'\n'/<br>}")

if ((${#rows[@]} == 0)); then
  echo 'No team stacks are affected by this change.'
else
  echo '| Env | Team | Changes |'
  echo '|---|---|---|'
  printf '%s\n' "${rows[@]}" | sort
  echo
  $public && echo '⚠️ **Public exposure:** objects in buckets marked public will be readable by anyone. Check the justification.' && echo
  $failed && printf '%s\n' "${details[@]}" && echo
  $retained && echo '📦 **Retain:** removed from the team file but not empty, so it is kept private and tagged `platform:lifecycle=retained` instead of deleted.' && echo
fi
echo
echo '**Next:** code-owner review → merge → dev and staging apply automatically → prod applies after platform approval.'
