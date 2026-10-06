#!/usr/bin/env bash
# End-to-end test: the real tf.sh against MiniStack on localhost:4566.
# Usage: make e2e
set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
E2E_DIR="$REPO/tests/e2e"
E2E_OUT="$REPO/.out/e2e"
source "$E2E_DIR/lib.sh"

for tool in tofu aws jq curl conftest; do command -v "$tool" >/dev/null || die "missing required tool: $tool"; done

# Fake credentials for the emulator.
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_REGION=eu-central-1 AWS_DEFAULT_REGION=eu-central-1
export AWS_ENDPOINT_URL=http://localhost:4566 AWS_PAGER=""
[[ -f "$REPO/.tofu-mirror/tofurc" ]] && export TF_CLI_CONFIG_FILE="$REPO/.tofu-mirror/tofurc"

# Work on a copy of the test teams, so the repo is never touched.
rm -rf "$E2E_OUT" "$REPO/.out/local"
mkdir -p "$E2E_OUT/logs"
cp -R "$E2E_DIR/teams" "$E2E_OUT/teams"
export TEAMS_DIR="$E2E_OUT/teams" TF_DATA_ROOT="$E2E_OUT/tfdata"

echo "Using MiniStack at $AWS_ENDPOINT_URL..."
curl -fsS "$AWS_ENDPOINT_URL/_ministack/health" >/dev/null || die "MiniStack is not reachable (make ministack-up ministack-forward)"
curl -fsS -X POST "$AWS_ENDPOINT_URL/_ministack/reset" >/dev/null

# Set up the emulated account like a platform admin would.
bootstrap() {
  local action=$1; shift
  TF_DATA_DIR="$E2E_OUT/tfdata/bootstrap-local" TF_INPUT=0 tofu -chdir="$REPO/bootstrap" "$action" "$@"
}
echo "Bootstrapping the emulated account..."
bootstrap init "-backend-config=path=$E2E_OUT/bootstrap-local.tfstate" >"$E2E_OUT/logs/bootstrap.log" 2>&1
bootstrap apply -auto-approve -var-file=envs/local.tfvars >>"$E2E_OUT/logs/bootstrap.log" 2>&1 \
  || die "bootstrap failed (see .out/e2e/logs/bootstrap.log)"

for f in "$E2E_DIR"/scenarios/[0-9]*.sh; do source "$f"; done

printf '\n===== e2e summary =====\n'
printf '%s\n' "${E2E_RESULTS[@]}"
if (( E2E_FAILURES > 0 )); then
  printf '%d check(s) failed. Logs: .out/e2e/logs/\n' "$E2E_FAILURES"; exit 1
fi
echo "All e2e checks passed."
