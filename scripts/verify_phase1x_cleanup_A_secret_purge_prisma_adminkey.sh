#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; exit 1; }
check_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -Fq "$pattern" "$file"; then pass "$label"; else fail "$label"; fi
}
check_not_exists() {
  local file="$1" label="$2"
  if [[ ! -e "$file" ]]; then pass "$label"; else fail "$label"; fi
}
check_exists() {
  local file="$1" label="$2"
  if [[ -e "$file" ]]; then pass "$label"; else fail "$label"; fi
}

GITIGNORE="$ROOT/.gitignore"
LIB_PRISMA="$ROOT/apps/api/src/lib/prisma.ts"
SRC_PRISMA="$ROOT/apps/api/src/prisma.ts"
INFRA_PRISMA="$ROOT/apps/api/src/infra/prisma.ts"
ADMIN_KEY="$ROOT/apps/api/src/infra/adminKey.ts"
SECRET_PEM="$ROOT/apps/api/secrets/agent_cmmcxp5so0002n86wsrcajdgp_private.pem"
KEEP="$ROOT/apps/api/secrets/.gitkeep"

check_not_exists "$SECRET_PEM" "committed agent private key removed from working tree"
check_exists "$KEEP" "secrets directory preserved with .gitkeep"
check_contains "$GITIGNORE" "*.pem" ".gitignore blocks pem keys"
check_contains "$GITIGNORE" "secrets/" ".gitignore blocks secrets directory"
check_contains "$GITIGNORE" "docker-compose-backup*.yml" ".gitignore blocks compose backup files"

check_contains "$LIB_PRISMA" "new PrismaClient()" "lib/prisma.ts creates canonical Prisma client"
check_contains "$LIB_PRISMA" "__dcapxPrisma" "lib/prisma.ts uses global singleton guard"
check_contains "$SRC_PRISMA" 'export { prisma, default } from "./lib/prisma";' "src/prisma.ts re-exports canonical Prisma client"
check_contains "$INFRA_PRISMA" 'export { prisma, default } from "../lib/prisma";' "infra/prisma.ts re-exports canonical Prisma client"

check_contains "$ADMIN_KEY" 'throw new Error("ADMIN_KEY is required")' "adminKey throws when ADMIN_KEY is missing"
if grep -Fq 'change-me-now-please' "$ADMIN_KEY"; then
  fail "adminKey fallback removed"
else
  pass "adminKey fallback removed"
fi

echo
echo "All Phase 1.x Cleanup A static checks passed."
