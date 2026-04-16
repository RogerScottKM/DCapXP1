#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${1:-$DEFAULT_ROOT}"

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
SRC="$ROOT/apps/api/src/middleware/require-auth.ts"
TEST="$ROOT/apps/api/test/require-auth.comprehensive.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$SRC" ] || fail "require-auth.ts exists"
[ -f "$TEST" ] || fail "require-auth comprehensive test exists"

contains "$PKG" '"test:auth:require-auth"' "package.json includes require-auth test script"
contains "$PKG" 'vitest run test/require-auth.comprehensive.test.ts' "package.json require-auth script points at focused test file"

contains "$SRC" 'const mode = bodyMode ?? queryMode ?? headerMode;' "middleware prefers body, then query, then header mode"
contains "$SRC" 'status: "APPROVED"' "middleware requires approved KYC for LIVE mode"
contains "$SRC" 'AUTHZ_UNAUTHENTICATED_DENIED' "middleware audits unauthenticated denials"
contains "$SRC" 'AUTHZ_ROLE_DENIED' "middleware audits role denials"
contains "$SRC" 'AUTHZ_MFA_REQUIRED_DENIED' "middleware audits MFA denials"
contains "$SRC" 'AUTHZ_ADMIN_ROLE_DENIED' "middleware audits admin role denials"
contains "$SRC" 'AUTHZ_ADMIN_MFA_REQUIRED_DENIED' "middleware audits admin MFA denials"
contains "$SRC" 'AUTHZ_LIVE_MFA_REQUIRED_DENIED' "middleware audits LIVE MFA denials"
contains "$SRC" 'LIVE_MODE_DENIED' "middleware audits LIVE KYC denials"
contains "$SRC" 'allowedRoleCodes: string[] = ["ADMIN", "AUDITOR"]' "middleware defaults admin recent MFA roles to ADMIN and AUDITOR"

contains "$TEST" 'vi.mock("../src/lib/service/security-audit"' "test file mocks security audit persistence"
contains "$TEST" 'passes exactly at the maxAge boundary' "test file covers exact MFA boundary pass"
contains "$TEST" 'rejects just beyond the maxAge boundary' "test file covers just-beyond MFA boundary rejection"
contains "$TEST" 'rejects LIVE mode when KYC is pending' "test file covers LIVE denial for pending KYC"
contains "$TEST" 'rejects LIVE mode when KYC is under review' "test file covers LIVE denial for under-review KYC"
contains "$TEST" 'rejects LIVE mode when KYC is rejected' "test file covers LIVE denial for rejected KYC"
contains "$TEST" 'uses body mode ahead of query and header mode' "test file covers mode precedence"
contains "$TEST" 'reads LIVE mode from query string' "test file covers query mode"
contains "$TEST" 'reads LIVE mode from x-mode header' "test file covers header mode"
contains "$TEST" 'is case-insensitive for requested mode' "test file covers case-insensitive mode handling"


echo
echo "Resolved repo root: $ROOT"
echo "All Phase 17 A3 static checks passed."
