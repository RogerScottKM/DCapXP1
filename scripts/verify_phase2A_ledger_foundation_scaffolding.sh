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

SCHEMA="$ROOT/apps/api/prisma/schema.prisma"
MIGRATION="$ROOT/apps/api/prisma/migrations/20260411_phase2a_ledger_foundation/migration.sql"
POSTING="$ROOT/apps/api/src/lib/ledger/posting.ts"
ACCOUNTS="$ROOT/apps/api/src/lib/ledger/accounts.ts"
SERVICE="$ROOT/apps/api/src/lib/ledger/service.ts"
INDEX="$ROOT/apps/api/src/lib/ledger/index.ts"
TEST_FILE="$ROOT/apps/api/test/ledger.posting.test.ts"
PACKAGE_JSON="$ROOT/apps/api/package.json"

check_contains "$PACKAGE_JSON" '"test:ledger"' "package.json includes ledger test script"

check_contains "$SCHEMA" 'enum LedgerAccountOwnerType' "schema.prisma adds LedgerAccountOwnerType enum"
check_contains "$SCHEMA" 'enum LedgerAccountType' "schema.prisma adds LedgerAccountType enum"
check_contains "$SCHEMA" 'enum LedgerTransactionStatus' "schema.prisma adds LedgerTransactionStatus enum"
check_contains "$SCHEMA" 'enum LedgerPostingSide' "schema.prisma adds LedgerPostingSide enum"
check_contains "$SCHEMA" 'model LedgerAccount {' "schema.prisma adds LedgerAccount model"
check_contains "$SCHEMA" 'model LedgerTransaction {' "schema.prisma adds LedgerTransaction model"
check_contains "$SCHEMA" 'model LedgerPosting {' "schema.prisma adds LedgerPosting model"
check_contains "$SCHEMA" '@@unique([ownerType, ownerRef, assetCode, mode, accountType])' "schema.prisma adds unique ledger account key"
check_contains "$SCHEMA" 'amount        Decimal' "schema.prisma stores ledger posting amount as Decimal"

check_contains "$MIGRATION" 'CREATE TABLE IF NOT EXISTS "LedgerAccount"' "migration creates LedgerAccount table"
check_contains "$MIGRATION" 'CREATE TABLE IF NOT EXISTS "LedgerTransaction"' "migration creates LedgerTransaction table"
check_contains "$MIGRATION" 'CREATE TABLE IF NOT EXISTS "LedgerPosting"' "migration creates LedgerPosting table"
check_contains "$MIGRATION" 'CREATE UNIQUE INDEX IF NOT EXISTS "LedgerAccount_ownerType_ownerRef_assetCode_mode_accountType_key"' "migration creates ledger account uniqueness index"
check_contains "$MIGRATION" 'CREATE INDEX IF NOT EXISTS "LedgerPosting_assetCode_createdAt_idx"' "migration creates ledger posting asset/time index"

check_contains "$POSTING" 'assertBalancedPostings' "posting helper exports balance assertion"
check_contains "$POSTING" 'buildLedgerTransfer' "posting helper exports transfer builder"
check_contains "$POSTING" 'Ledger transaction must include at least two postings.' "posting helper enforces minimum postings"
check_contains "$POSTING" 'Ledger postings are not balanced for asset' "posting helper enforces per-asset balance"

check_contains "$ACCOUNTS" 'ensureLedgerAccount' "accounts helper exports ensureLedgerAccount"
check_contains "$ACCOUNTS" 'ensureUserLedgerAccounts' "accounts helper exports ensureUserLedgerAccounts"
check_contains "$ACCOUNTS" 'ensureSystemLedgerAccounts' "accounts helper exports ensureSystemLedgerAccounts"
check_contains "$ACCOUNTS" 'SYSTEM_LEDGER_OWNER_REF' "accounts helper defines system owner ref"

check_contains "$SERVICE" 'postLedgerTransaction' "ledger service exports postLedgerTransaction"
check_contains "$SERVICE" 'assertBalancedPostings' "ledger service uses posting balance assertion"
check_contains "$SERVICE" 'createMany' "ledger service persists postings in bulk"
check_contains "$SERVICE" 'status: "POSTED"' "ledger service creates posted transactions"

check_contains "$INDEX" 'export * from "./posting";' "ledger index re-exports posting helper"
check_contains "$INDEX" 'export * from "./accounts";' "ledger index re-exports accounts helper"
check_contains "$INDEX" 'export * from "./service";' "ledger index re-exports service helper"

check_contains "$TEST_FILE" 'accepts balanced postings' "ledger test covers balanced postings"
check_contains "$TEST_FILE" 'rejects unbalanced postings' "ledger test covers unbalanced postings"
check_contains "$TEST_FILE" 'buildLedgerTransfer creates a balanced transfer pair' "ledger test covers transfer builder"

echo
echo "All Phase 2A static checks passed."
