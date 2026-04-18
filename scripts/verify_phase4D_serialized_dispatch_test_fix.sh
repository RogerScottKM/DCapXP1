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

DISPATCH="$ROOT/apps/api/src/lib/matching/serialized-dispatch.ts"
TEST="$ROOT/apps/api/test/matching-serialized-dispatch.test.ts"
PKG="$ROOT/apps/api/package.json"

[ -f "$DISPATCH" ] || fail "serialized-dispatch.ts exists"
[ -f "$TEST" ] || fail "matching-serialized-dispatch.test.ts exists"
[ -f "$PKG" ] || fail "package.json exists"

contains "$DISPATCH" 'const run = previous.catch(() => undefined).then(taskFactory);' "dispatcher chains work after the previous lane"
contains "$DISPATCH" 'const tracked = run.finally(() => {' "dispatcher tracks the final promise for cleanup"
contains "$DISPATCH" 'if (lanes.get(key) === tracked) {' "dispatcher only clears the active tracked lane"
contains "$DISPATCH" 'return tracked;' "dispatcher returns the tracked promise"
contains "$PKG" '"test:matching:serialized-dispatch"' "package.json still includes serialized dispatch test script"
contains "$TEST" 'expect(getSerializedLaneCount()).toBe(0);' "focused test still asserts that lanes fully drain"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused Phase 4D tests"
if (cd "$ROOT" && pnpm --filter api test:matching:serialized-dispatch); then
  pass "focused Phase 4D tests pass"
else
  fail "focused Phase 4D tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Phase 4D fix checks passed."
