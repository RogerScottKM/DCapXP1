#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 1 && -n "${1:-}" ]]; then
  ROOT="$1"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; exit 1; }
contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -Fq "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}

PKG="$ROOT/apps/api/package.json"
SERVER="$ROOT/apps/api/src/server.ts"
WORKER="$ROOT/apps/api/src/workers/reconciliation.ts"
TEST="$ROOT/apps/api/test/reconciliation.worker.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$SERVER" ] || fail "server.ts exists"
[ -f "$WORKER" ] || fail "workers/reconciliation.ts exists"
[ -f "$TEST" ] || fail "reconciliation.worker.test.ts exists"

contains "$PKG" '"test:workers:reconciliation"' "package.json includes reconciliation worker test script"
contains "$PKG" 'vitest run test/reconciliation.worker.test.ts' "package.json worker test script points at focused test file"

contains "$SERVER" 'import { bootstrapSecrets } from "./lib/bootstrap-secrets";' "server imports bootstrapSecrets"
contains "$SERVER" 'startReconciliationWorker' "server imports or uses startReconciliationWorker"
contains "$SERVER" 'stopReconciliationWorker' "server imports or uses stopReconciliationWorker"
contains "$SERVER" 'RECONCILIATION_ENABLED' "server checks RECONCILIATION_ENABLED"
contains "$SERVER" 'RECONCILIATION_INTERVAL_MS' "server reads RECONCILIATION_INTERVAL_MS"
contains "$SERVER" 'await bootstrapSecrets();' "server bootstraps secrets before startup"
contains "$SERVER" 'stopReconciliationWorker();' "server stops worker during shutdown"
contains "$SERVER" 'startReconciliationWorker(RECON_INTERVAL_MS);' "server starts worker using configured interval"

contains "$WORKER" 'export async function runReconciliation()' "worker exports runReconciliation"
contains "$WORKER" 'export function startReconciliationWorker' "worker exports startReconciliationWorker"
contains "$WORKER" 'export function stopReconciliationWorker' "worker exports stopReconciliationWorker"

contains "$TEST" 'passes all checks on a healthy empty ledger' "worker tests cover healthy empty ledger"
contains "$TEST" 'detects global balance mismatch and logs audit event' "worker tests cover balance mismatch"
contains "$TEST" 'detects negative account balances' "worker tests cover negative balances"
contains "$TEST" 'detects missing trade settlements' "worker tests cover missing settlements"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused reconciliation worker tests"
if (cd "$ROOT" && pnpm --filter api test:workers:reconciliation); then
  pass "focused reconciliation worker tests pass"
else
  fail "focused reconciliation worker tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 2L checks passed."
