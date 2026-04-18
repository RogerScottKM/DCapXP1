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
SCRIPT="$ROOT/apps/api/src/scripts/vault-exec.ts"
TEST="$ROOT/apps/api/test/vault-exec.script.test.ts"
COMPOSE="$ROOT/docker-compose.yml"

[ -f "$PKG" ] || fail "package.json exists"
[ -f "$SCRIPT" ] || fail "vault-exec.ts exists"
[ -f "$TEST" ] || fail "vault-exec.script.test.ts exists"
[ -f "$COMPOSE" ] || fail "docker-compose.yml exists"

contains "$PKG" '"vault:exec": "node dist/scripts/vault-exec.js"' "package.json includes vault:exec script"
contains "$PKG" '"prisma:migrate:vault": "pnpm build && node dist/scripts/vault-exec.js pnpm prisma migrate deploy"' "package.json includes prisma:migrate:vault script"
contains "$PKG" '"start:vault": "pnpm build && node dist/scripts/vault-exec.js node dist/server.js"' "package.json includes start:vault script"
contains "$PKG" '"boot:vault": "node dist/scripts/vault-exec.js sh -lc \"pnpm prisma migrate deploy && node dist/server.js\""' "package.json includes boot:vault script"
contains "$PKG" '"test:vault-exec": "vitest run test/vault-exec.script.test.ts"' "package.json includes vault-exec focused test script"

contains "$SCRIPT" 'import { bootstrapSecrets } from "../lib/bootstrap-secrets";' "vault-exec imports bootstrapSecrets"
contains "$SCRIPT" 'export async function runVaultExec' "vault-exec exports runVaultExec"
contains "$SCRIPT" 'await bootstrapSecrets();' "vault-exec bootstraps secrets before child command"
contains "$SCRIPT" 'const [command, ...args] = argv;' "vault-exec resolves command arguments"
contains "$SCRIPT" 'const child = spawnImpl(command, args, options);' "vault-exec spawns child command"
contains "$SCRIPT" 'if (require.main === module)' "vault-exec supports direct CLI execution"

contains "$TEST" 'bootstraps secrets before spawning a child command' "vault-exec test covers bootstrap before spawn"
contains "$TEST" 'throws when no command is provided' "vault-exec test covers missing command"
contains "$TEST" 'rejects when the child exits non-zero' "vault-exec test covers child failure"

contains "$COMPOSE" 'pnpm boot:vault' "docker-compose api command uses pnpm boot:vault"

echo "[INFO] Running api build"
if (cd "$ROOT" && pnpm --filter api build); then
  pass "api build passes"
else
  fail "api build passes"
fi

echo "[INFO] Running focused vault-exec tests"
if (cd "$ROOT" && pnpm --filter api test:vault-exec); then
  pass "focused vault-exec tests pass"
else
  fail "focused vault-exec tests pass"
fi

echo
echo "Resolved repo root: $ROOT"
echo "All Vault-first migration checks passed."
