#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; exit 1; }

check_contains() {
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
RECON="$ROOT/apps/api/src/lib/ledger/reconciliation.ts"
INDEX="$ROOT/apps/api/src/lib/ledger/index.ts"
TRADE="$ROOT/apps/api/src/routes/trade.ts"
TEST="$ROOT/apps/api/test/ledger.reconciliation.test.ts"

check_contains "$PKG" '"test:ledger:settlement"' "package.json includes ledger settlement test script"

check_contains "$RECON" 'assertTradeSettlementConsistency' "reconciliation helper exports consistency assertion"
check_contains "$RECON" 'reconcileTradeSettlement' "reconciliation helper exports reconciliation loader"
check_contains "$RECON" 'referenceId' "reconciliation helper checks reference id"
check_contains "$RECON" 'metadata.symbol' "reconciliation helper checks metadata symbol"
check_contains "$RECON" 'postingCount' "reconciliation helper returns posting summary"

check_contains "$INDEX" 'export * from "./reconciliation";' "ledger index re-exports reconciliation helper"

check_contains "$TRADE" 'router.post("/fills/demo"' "trade route exposes demo fill settlement route"
check_contains "$TRADE" 'settleMatchedTrade' "trade route settles matched fills into ledger"
check_contains "$TRADE" 'tx.trade.create' "trade route creates Trade records before settlement"
check_contains "$TRADE" 'status: "FILLED"' "trade route updates filled orders"
check_contains "$TRADE" 'reconcileTradeSettlement' "trade route runs reconciliation after settlement"
check_contains "$TRADE" 'quoteFee' "trade route supports fee booking"
check_contains "$TRADE" 'Phase 2C demo fill path' "trade route documents narrowed fill scope"

check_contains "$TEST" 'accepts a consistent trade settlement record' "reconciliation test covers successful settlement"
check_contains "$TEST" 'rejects mismatched settlement metadata' "reconciliation test covers metadata mismatch"
check_contains "$TEST" 'rejects ledger transactions without enough postings' "reconciliation test covers posting-count mismatch"

echo
echo "All Phase 2C static checks passed."
