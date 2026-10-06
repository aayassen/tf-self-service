#!/usr/bin/env bash
# Tests for scripts/ci/changes.sh and check.sh, using a throwaway git repo.
# Usage: make ci-test
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; failures=$((failures + 1)); }

team_file() { # <team> [buckets]: prints a valid team file
  cat <<EOF
schema_version: 1
owner: { github_team: my-org/$1, contact: "#$1", cost_center: CC-1 }
workload: { namespace: $1, service_account: app }
buckets:
${2:-"  - { name: data, visibility: private }"}
EOF
}

# A new repo with three teams in every environment.
fresh() {
  rm -rf "$WORK/r"; mkdir -p "$WORK/r"; cd "$WORK/r"
  cp -R "$REPO/schema" "$REPO/scripts" .
  mkdir -p modules/team && echo "# platform module" >modules/team/main.tf
  for t in alpha beta gamma; do
    mkdir -p "teams/$t"
    for e in dev staging prod; do team_file "$t" >"teams/$t/$e.yaml"; done
  done
  git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm base
}
commit() { git add -A && git -c user.email=t@t -c user.name=t commit -qm change; }
check() { scripts/ci/check.sh HEAD~1 HEAD 2>&1; }

expect_ok() { # <name>
  local out; if out=$(check); then pass "$1"; else fail "$1"; printf '%s\n' "$out" | sed 's/^/      /'; fi
}
expect_problem() { # <name> <expected message>
  local out status=0; out=$(check) || status=$?
  if [[ $status != 0 && $out == *"$2"* ]]; then pass "$1"; else fail "$1 (status $status)"; printf '%s\n' "$out" | sed 's/^/      /'; fi
}
expect_matrix() { # <name> <expected> [changes.sh args...]
  local name=$1 want=$2 got; shift 2
  got=$(scripts/ci/changes.sh "$@" | jq -c '[.include[] | "\(.env) \(.stacks)"]')
  [[ $got == "$want" ]] && pass "$name" || fail "$name: expected $want, got $got"
}

echo "changes.sh"
fresh; team_file alpha "  - { name: data, visibility: private }
  - { name: logs, visibility: private }" >teams/alpha/dev.yaml; commit
expect_matrix "one team file → one stack" '["dev alpha:apply"]' HEAD~1 HEAD
fresh; git rm -q teams/beta/prod.yaml; commit
expect_matrix "deleted team file → destroy" '["prod beta:destroy"]' HEAD~1 HEAD
fresh; echo "# change" >>modules/team/main.tf; commit
expect_matrix "platform change → every stack" \
  '["dev alpha:apply beta:apply gamma:apply","prod alpha:apply beta:apply gamma:apply","staging alpha:apply beta:apply gamma:apply"]' HEAD~1 HEAD
expect_matrix "env filter" '["prod alpha:apply beta:apply gamma:apply"]' HEAD~1 HEAD prod
BATCH_SIZE=2 expect_matrix "batching" '["dev alpha:apply beta:apply","dev gamma:apply"]' --all dev
fresh; echo "x" >README.md; commit
expect_matrix "unrelated change → nothing" '[]' HEAD~1 HEAD

echo "check.sh"
fresh; team_file alpha "  - { name: data, visibility: private }
  - { name: site, visibility: public, public: { mode: cloudfront, justification: web } }" >teams/alpha/prod.yaml; commit
expect_ok "valid team change"
fresh; mkdir teams/delta; team_file delta >teams/delta/qa.yaml; commit
expect_problem "unknown env file" "teams/<team>/<dev|staging|prod>.yaml"
fresh; mkdir teams/Delta; team_file delta >teams/Delta/dev.yaml; commit
expect_problem "invalid team folder" "teams/<team>/<dev|staging|prod>.yaml"
fresh; team_file alpha "  - { name: x, visibility: private }" >teams/alpha/dev.yaml
team_file beta "  - { name: x, visibility: private }" >teams/beta/dev.yaml; commit
expect_problem "two teams in one PR" "more than one team"
fresh; team_file alpha "  - { name: x, visibility: private }" >teams/alpha/dev.yaml; echo "#" >>modules/team/main.tf; commit
expect_problem "team + platform change" "mixes team files with platform code"
fresh; team_file alpha "  - { name: data }" >teams/alpha/dev.yaml; commit
expect_problem "missing visibility (schema)" "does not match schema"
fresh; team_file alpha "  - { name: data, visibility: private, size: big }" >teams/alpha/dev.yaml; commit
expect_problem "unknown field (schema)" "does not match schema"
fresh; { team_file alpha; echo "schema_version: 1"; } >teams/alpha/dev.yaml; commit
expect_problem "duplicate YAML key" "does not match schema"
fresh; team_file alpha "  - { name: logs, visibility: private }" >teams/alpha/dev.yaml; commit
expect_problem "active bucket removed" "bucket 'data' removed while active"
fresh; team_file alpha "  - { name: data, visibility: private, lifecycle: decommission }
  - { name: logs, visibility: private }" >teams/alpha/dev.yaml; commit
team_file alpha "  - { name: logs, visibility: private }" >teams/alpha/dev.yaml; commit
expect_ok "decommissioned bucket removed"
fresh; git rm -q teams/alpha/dev.yaml; commit
expect_problem "active team file deleted" "deleted before the team was decommissioned"
fresh; { team_file alpha; echo "lifecycle: decommission"; } >teams/alpha/dev.yaml; commit
git rm -q teams/alpha/dev.yaml; commit
expect_ok "decommissioned team file deleted"
fresh; team_file alpha "  - { name: data, visibility: public, public: { mode: direct, justification: x } }" >teams/alpha/prod.yaml; commit
expect_problem "direct public in prod needs approval" "needs an approving review"
PLATFORM_APPROVED=true expect_ok "direct public in prod with platform approval"
fresh; team_file alpha "  - { name: data, visibility: public, public: { mode: direct, justification: x } }" >teams/alpha/dev.yaml; commit
expect_ok "direct public in dev needs no approval"

echo "summarize.sh"
mkdir -p "$WORK/s/dev/alpha" "$WORK/s/dev/beta"
echo '{}' >"$WORK/s/dev/alpha/plan.json"          # a plan with no resources at all
echo "boom" >"$WORK/s/dev/beta/error.txt"
out=$("$REPO/scripts/ci/summarize.sh" "$WORK/s" 2>&1) || true
[[ $out == *"1 team stack(s) with no changes"* ]] && pass "empty plan counts as no changes" || fail "empty plan: $out"
[[ $out == *"| dev | beta | ❌ failed"* && $out == *"boom"* ]] && pass "failed team shown with its error" || fail "failed team: $out"

echo
if ((failures > 0)); then echo "$failures CI script test(s) failed."; exit 1; fi
echo "All CI script tests passed."
