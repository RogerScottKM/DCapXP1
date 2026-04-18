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
RUNTIME="$ROOT/apps/api/src/lib/runtime/runtime-status.ts"
TEST_LIB="$ROOT/apps/api/test/runtime-status.lib.test.ts"
TEST_ROUTE="$ROOT/apps/api/test/runtime-status.routes.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$SERVER" ] || fail "server.ts exists"
[ -f "$RUNTIME" ] || fail "runtime-status.ts exists"
[ -f "$TEST_LIB" ] || fail "runtime-status.lib.test.ts exists"
[ -f "$TEST_ROUTE" ] || fail "runtime-status.routes.test.ts exists"

contains "$PKG" '"test:runtime:status"' "package.json still includes runtime status test script"
contains "$SERVER" 'import { markRuntimeStarted, markRuntimeStopped } from "./lib/runtime/runtime-status";' "server imports runtime lifecycle helpers"
contains "$SERVER" 'markRuntimeStopped(signal);' "server marks runtime stopped during shutdown"
contains "$SERVER" 'markRuntimeStarted({' "server marks runtime started after boot"
contains "$SERVER" 'reconciliationEnabled: reconEnabled,' "server passes reconciliationEnabled into runtime status"
contains "$SERVER" 'reconciliationIntervalMs: RECON_INTERVAL_MS,' "server passes reconciliation interval into runtime status"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused Phase 5A tests"
if (cd "$ROOT" && pnpm --filter api test:runtime:status); then
  pass "focused Phase 5A tests pass"
else
  fail "focused Phase 5A tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 5A server-start fix checks passed."
