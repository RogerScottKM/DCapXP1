#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

pass() {
  echo "[PASS] $1"
}

fail() {
  echo "[FAIL] $1"
  exit 1
}

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

AUDIT_HELPER="$ROOT/apps/api/src/lib/service/security-audit.ts"
AUDIT_MIDDLEWARE="$ROOT/apps/api/src/middleware/audit-privileged.ts"
MFA_SERVICE="$ROOT/apps/api/src/modules/auth/mfa.service.ts"
AUTH_CONTROLLER="$ROOT/apps/api/src/modules/auth/auth.controller.ts"
AGENTS="$ROOT/apps/api/src/routes/agents.ts"
MANDATES="$ROOT/apps/api/src/routes/mandates.ts"
ADVISOR_ROUTES="$ROOT/apps/api/src/modules/advisor/advisor.routes.ts"
INVITATIONS_ROUTES="$ROOT/apps/api/src/modules/invitations/invitations.routes.ts"

check_contains "$AUDIT_HELPER" "prisma.auditEvent.create" "security-audit helper persists audit events"
check_contains "$AUDIT_HELPER" "ipAddress" "security-audit helper records IP addresses"
check_contains "$AUDIT_HELPER" "userAgent" "security-audit helper records user agents"
check_contains "$AUDIT_HELPER" "actorType" "security-audit helper records actor types"

check_contains "$AUDIT_MIDDLEWARE" "recordSecurityAudit" "audit-privileged middleware calls security audit helper"
check_contains "$AUDIT_MIDDLEWARE" "auditPrivilegedRequest" "audit-privileged middleware exports auditPrivilegedRequest"

check_contains "$MFA_SERVICE" "MFA_TOTP_ENROLLMENT_STARTED" "mfa.service.ts audits TOTP enrollment start"
check_contains "$MFA_SERVICE" "MFA_TOTP_ENROLLMENT_ACTIVATED" "mfa.service.ts audits TOTP activation"
check_contains "$MFA_SERVICE" "MFA_RECOVERY_CODES_REGENERATED" "mfa.service.ts audits recovery code regeneration"
check_contains "$MFA_SERVICE" "MFA_CHALLENGE_SUCCEEDED" "mfa.service.ts audits MFA challenge success"
check_contains "$MFA_SERVICE" "SESSION_REVOKED_AFTER_MFA_CHANGE" "mfa.service.ts audits session revocation after MFA change"
check_contains "$MFA_SERVICE" "tx.session.updateMany" "mfa.service.ts revokes other sessions after MFA changes"
check_contains "$MFA_SERVICE" "mfaMethod: null" "mfa.service.ts clears current session MFA method after factor changes"
check_contains "$MFA_SERVICE" "mfaVerifiedAt: null" "mfa.service.ts clears current session MFA freshness after factor changes"

check_contains "$AUTH_CONTROLLER" "buildAuditContext" "auth.controller.ts builds audit context from request"
check_contains "$AUTH_CONTROLLER" "req.auth?.sessionId" "auth.controller.ts passes session id into MFA service calls"
check_contains "$AUTH_CONTROLLER" "req.get(\"user-agent\")" "auth.controller.ts passes user-agent into MFA service calls"

check_contains "$AGENTS" "auditPrivilegedRequest" "agents.ts audits privileged agent actions"
check_contains "$MANDATES" "auditPrivilegedRequest" "mandates.ts audits privileged mandate actions"
check_contains "$ADVISOR_ROUTES" "auditPrivilegedRequest" "advisor.routes.ts audits privileged advisor access"
check_contains "$INVITATIONS_ROUTES" "auditPrivilegedRequest" "invitations.routes.ts audits privileged invitation creation"
check_contains "$INVITATIONS_ROUTES" "INVITATION_CREATE_REQUESTED" "invitations.routes.ts records invitation create action"

echo

echo "All Phase 1.6 static checks passed."
