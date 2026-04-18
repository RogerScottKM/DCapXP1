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

TEST="$ROOT/apps/api/test/idempotency.lib.test.ts"
HELPER="$ROOT/apps/api/src/lib/idempotency.ts"
ORDERS="$ROOT/apps/api/src/routes/orders.ts"

[ -f "$TEST" ] || fail "idempotency.lib.test.ts exists"
[ -f "$HELPER" ] || fail "idempotency helper exists"
[ -f "$ORDERS" ] || fail "orders.ts exists"

contains "$TEST" 'const { store, prismaMock } = vi.hoisted(() => {' "idempotency test uses hoisted prisma mock"
contains "$TEST" 'vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));' "idempotency test mocks prisma via hoisted value"
contains "$TEST" 'replays the stored response for the same key and same payload' "idempotency tests cover same-key replay"
contains "$TEST" 'rejects the same key reused with a different payload' "idempotency tests cover same-key mismatch rejection"
contains "$TEST" 'runs normally when no idempotency key is provided' "idempotency tests cover optional key behavior"

contains "$HELPER" 'export function withIdempotency' "helper still exports withIdempotency"
contains "$ORDERS" 'withIdempotency("HUMAN_ORDER_PLACE"' "orders route still wraps placement with idempotency"
contains "$ORDERS" 'withIdempotency("HUMAN_ORDER_CANCEL"' "orders route still wraps cancel with idempotency"

echo "[INFO] Running focused idempotency tests"
if (cd "$ROOT" && pnpm --filter api test:lib:idempotency); then
  pass "focused idempotency tests pass"
else
  fail "focused idempotency tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 3B test-fix checks passed."
