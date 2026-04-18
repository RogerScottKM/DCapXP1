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

TEST="$ROOT/apps/api/test/in-memory-settlement-integration.test.ts"
[ -f "$TEST" ] || fail "in-memory-settlement-integration.test.ts exists"

contains "$TEST" '.mockResolvedValueOnce(new Decimal("3")) // first execute: sell order initial remaining' "4C test mocks first execute initial remaining"
contains "$TEST" '.mockResolvedValueOnce(new Decimal("3")) // first execute: sell order final refresh remaining' "4C test mocks first execute final refresh remaining"
contains "$TEST" '.mockResolvedValueOnce(new Decimal("2")) // second execute: buy order initial remaining' "4C test mocks second execute initial remaining"
contains "$TEST" '.mockResolvedValueOnce(new Decimal("0")); // second execute: buy order final refresh remaining after full fill' "4C test mocks second execute final refresh remaining"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused Phase 4C tests"
if (cd "$ROOT" && pnpm --filter api test:matching:in-memory-settlement); then
  pass "focused Phase 4C tests pass"
else
  fail "focused Phase 4C tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 4C test-fix checks passed."
