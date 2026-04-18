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

PKG="$ROOT/apps/api/package.json"
HELPER="$ROOT/apps/api/src/scripts/vault-bootstrap-env.ts"
VAULT_EXEC="$ROOT/apps/api/src/scripts/vault-exec.ts"
PRINT_CTX="$ROOT/apps/api/src/scripts/print-vault-context.ts"
TEST="$ROOT/apps/api/test/vault-auto-bootstrap.test.ts"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$HELPER" ] || fail "vault-bootstrap-env.ts exists"
[ -f "$VAULT_EXEC" ] || fail "vault-exec.ts exists"
[ -f "$PRINT_CTX" ] || fail "print-vault-context.ts exists"
[ -f "$TEST" ] || fail "vault-auto-bootstrap.test.ts exists"

contains "$PKG" '"test:vault-auto-bootstrap": "vitest run test/vault-auto-bootstrap.test.ts"' "package.json includes vault auto-bootstrap focused test script"

contains "$HELPER" 'export function findRepoRoot' "helper exports repo root finder"
contains "$HELPER" 'export function resolveVaultBootstrapFile' "helper exports bootstrap file resolver"
contains "$HELPER" 'export function loadVaultBootstrapEnv' "helper exports bootstrap env loader"
contains "$HELPER" '.env.vault.host' "helper targets repo-root .env.vault.host"

contains "$VAULT_EXEC" 'loadVaultBootstrapEnv(process.cwd(), __dirname);' "vault-exec auto-loads repo-root host bootstrap env"
contains "$VAULT_EXEC" 'await bootstrapSecrets();' "vault-exec still bootstraps secrets after auto-load"

contains "$PRINT_CTX" 'const bootstrapFile = loadVaultBootstrapEnv(process.cwd(), __dirname);' "vault-context auto-loads repo-root host bootstrap env"
contains "$PRINT_CTX" 'bootstrapFile,' "vault-context reports resolved bootstrap file"
contains "$PRINT_CTX" 'databaseUrlMasked: maskDatabaseUrl(env.DATABASE_URL)' "vault-context still masks DATABASE_URL"

contains "$TEST" 'finds the repo root and resolves .env.vault.host from repo root automatically' "tests cover repo-root resolution"
contains "$TEST" 'loads host bootstrap values without manual source when repo-root file exists' "tests cover auto-loading without manual source"
contains "$TEST" 'prefers VAULT_BOOTSTRAP_FILE when explicitly provided' "tests cover explicit bootstrap file override"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused auto-bootstrap tests"
if (cd "$ROOT" && pnpm --filter api test:vault-auto-bootstrap); then
  pass "focused auto-bootstrap tests pass"
else
  fail "focused auto-bootstrap tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All auto-bootstrap host Vault checks passed."
