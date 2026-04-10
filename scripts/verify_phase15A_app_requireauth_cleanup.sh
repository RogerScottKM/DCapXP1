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

PACKAGE_JSON="$ROOT/apps/api/package.json"
APP_TS="$ROOT/apps/api/src/app.ts"
REQUIRE_AUTH_TS="$ROOT/apps/api/src/middleware/require-auth.ts"

check_contains "$PACKAGE_JSON" '"helmet"' "package.json includes helmet dependency"

check_contains "$APP_TS" 'import helmet from "helmet";' "app.ts imports helmet"
check_contains "$APP_TS" 'app.disable("x-powered-by");' "app.ts disables x-powered-by"
check_contains "$APP_TS" 'contentSecurityPolicy: false' "app.ts configures helmet"
check_contains "$APP_TS" 'Permissions-Policy' "app.ts sets permissions policy"
check_contains "$APP_TS" 'for (const prefix of ["/api", "/backend-api"])' "app.ts mounts API routers on both public prefixes"
check_contains "$APP_TS" 'for (const prefix of ["", "/v1/market", "/api/v1/market"])' "app.ts mounts market routes via grouped prefixes"
check_contains "$APP_TS" 'for (const prefix of ["", "/v1/trade", "/api/v1/trade"])' "app.ts mounts trade routes via grouped prefixes"
check_contains "$APP_TS" 'for (const prefix of ["", "/v1/stream", "/api/v1/stream"])' "app.ts mounts stream routes via grouped prefixes"
check_contains "$APP_TS" 'code: "NOT_FOUND"' "app.ts returns JSON 404 responses"

check_contains "$REQUIRE_AUTH_TS" 'import { prisma } from "../lib/prisma";' "require-auth.ts imports prisma"
check_contains "$REQUIRE_AUTH_TS" 'roleCodes: string[];' "require-auth.ts enriches auth context with role codes"
check_contains "$REQUIRE_AUTH_TS" 'mfaSatisfied: boolean;' "require-auth.ts reserves MFA status in auth context"
check_contains "$REQUIRE_AUTH_TS" 'await prisma.roleAssignment.findMany' "require-auth.ts loads role assignments"
check_contains "$REQUIRE_AUTH_TS" 'export function requireRole' "require-auth.ts exports requireRole helper"
check_contains "$REQUIRE_AUTH_TS" 'code: "FORBIDDEN"' "require-auth.ts returns FORBIDDEN for missing roles"

echo
echo "All Pass A static checks passed."
