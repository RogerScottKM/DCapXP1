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

AGENTS="$ROOT/apps/api/src/routes/agents.ts"
MANDATES="$ROOT/apps/api/src/routes/mandates.ts"
ADVISOR="$ROOT/apps/api/src/modules/advisor/advisor.routes.ts"
INVITES="$ROOT/apps/api/src/modules/invitations/invitations.routes.ts"
TRADE="$ROOT/apps/api/src/routes/trade.ts"

check_contains "$AGENTS" 'requireRecentMfa()' 'agents.ts applies recent MFA to agent create/rotate/revoke actions'
check_contains "$MANDATES" 'requireLiveModeEligible()' 'mandates.ts applies LIVE eligibility to mandate issuance'
check_contains "$MANDATES" 'requireRecentMfa()' 'mandates.ts applies recent MFA to mandate issue/revoke actions'
check_contains "$ADVISOR" 'requireRole("advisor", "admin")' 'advisor.routes.ts restricts advisor summary to advisor/admin roles'
check_contains "$ADVISOR" 'requireAdminRecentMfa' 'advisor.routes.ts can enforce admin recent MFA when caller is admin/auditor'
check_contains "$ADVISOR" 'requireRecentMfa' 'advisor.routes.ts enforces recent MFA for advisor/admin summary access'
check_contains "$INVITES" 'requireRole("advisor", "admin")' 'invitations.routes.ts restricts invitation creation to advisor/admin roles'
check_contains "$INVITES" 'requireAdminRecentMfa' 'invitations.routes.ts can enforce admin recent MFA when caller is admin/auditor'
check_contains "$INVITES" 'requireRecentMfa' 'invitations.routes.ts enforces recent MFA for invitation creation'
check_contains "$TRADE" 'enforceMandate("TRADE")' 'trade.ts remains agent-principal enforced and is intentionally unchanged'

echo

echo "All Pass 1.5D static checks passed."
