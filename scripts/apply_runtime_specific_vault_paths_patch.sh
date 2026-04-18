#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 1 && -n "${1:-}" ]]; then
  ROOT="$1"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import re
import sys
from textwrap import dedent

root = Path(sys.argv[1])

pkg_path = root / "apps/api/package.json"
compose_path = root / "docker-compose.yml"
env_example_path = root / ".env.vault.host.example"
script_path = root / "apps/api/src/scripts/print-vault-context.ts"
test_path = root / "apps/api/test/vault-context.script.test.ts"

for p in [pkg_path, compose_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["vault:verify"] = "pnpm build && node dist/scripts/print-vault-context.js"
scripts["test:vault-context"] = "vitest run test/vault-context.script.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

env_example_path.write_text(dedent("""\
# Host-side Vault bootstrap example for local Prisma / CLI usage.
# Keep the final DATABASE_URL inside Vault, not in this file.

VAULT_ENABLED=true
VAULT_ADDR=http://127.0.0.1:8200
VAULT_MOUNT_PATH=approle
VAULT_ROLE_ID=<HOST_APPROLE_ROLE_ID>
VAULT_SECRET_ID_FILE=/absolute/path/to/host-cli.secret-id
VAULT_SECRET_PATH=secret/data/dcapx/api-host
VAULT_OVERRIDE_ENV=true
"""))

script_path.parent.mkdir(parents=True, exist_ok=True)
script_path.write_text(dedent("""\
import "dotenv/config";

import { bootstrapSecrets } from "../lib/bootstrap-secrets";

export function maskDatabaseUrl(url?: string | null): string | null {
  if (!url) return null;
  return url.replace(/:([^:@/]+)@/, ":****@");
}

export async function collectVaultContext(
  env: NodeJS.ProcessEnv = process.env,
): Promise<Record<string, unknown>> {
  await bootstrapSecrets();

  return {
    VAULT_ENABLED: env.VAULT_ENABLED ?? null,
    hasVaultAddr: Boolean(env.VAULT_ADDR),
    hasVaultRoleId: Boolean(env.VAULT_ROLE_ID),
    hasVaultSecretId: Boolean(env.VAULT_SECRET_ID),
    hasVaultSecretIdFile: Boolean(env.VAULT_SECRET_ID_FILE),
    VAULT_SECRET_PATH: env.VAULT_SECRET_PATH ?? null,
    VAULT_OVERRIDE_ENV: env.VAULT_OVERRIDE_ENV ?? null,
    hasDatabaseUrl: Boolean(env.DATABASE_URL),
    databaseUrlMasked: maskDatabaseUrl(env.DATABASE_URL),
  };
}

async function main(): Promise<void> {
  try {
    const context = await collectVaultContext();
    console.log(JSON.stringify(context, null, 2));
  } catch (error) {
    console.error("[vault-context] failed", error);
    process.exit(1);
  }
}

if (require.main === module) {
  void main();
}
"""))

test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(dedent("""\
import { beforeEach, describe, expect, it, vi } from "vitest";

const { bootstrapSecrets } = vi.hoisted(() => ({
  bootstrapSecrets: vi.fn(),
}));

vi.mock("../src/lib/bootstrap-secrets", () => ({
  bootstrapSecrets,
}));

import { collectVaultContext, maskDatabaseUrl } from "../src/scripts/print-vault-context";

describe("vault context script", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    bootstrapSecrets.mockResolvedValue(undefined);
  });

  it("masks database URLs without exposing passwords", () => {
    expect(
      maskDatabaseUrl("postgresql://dcapx:SuperSecretPassword@127.0.0.1:5445/dcapx?schema=public"),
    ).toBe("postgresql://dcapx:****@127.0.0.1:5445/dcapx?schema=public");
  });

  it("collects a masked runtime-specific vault context after bootstrap", async () => {
    const context = await collectVaultContext({
      VAULT_ENABLED: "true",
      VAULT_ADDR: "http://127.0.0.1:8200",
      VAULT_ROLE_ID: "role-id",
      VAULT_SECRET_ID_FILE: "/tmp/host.secret-id",
      VAULT_SECRET_PATH: "secret/data/dcapx/api-host",
      VAULT_OVERRIDE_ENV: "true",
      DATABASE_URL: "postgresql://dcapx:HostPassword@127.0.0.1:5445/dcapx?schema=public",
    } as any);

    expect(bootstrapSecrets).toHaveBeenCalledTimes(1);
    expect(context).toEqual({
      VAULT_ENABLED: "true",
      hasVaultAddr: true,
      hasVaultRoleId: true,
      hasVaultSecretId: false,
      hasVaultSecretIdFile: true,
      VAULT_SECRET_PATH: "secret/data/dcapx/api-host",
      VAULT_OVERRIDE_ENV: "true",
      hasDatabaseUrl: true,
      databaseUrlMasked: "postgresql://dcapx:****@127.0.0.1:5445/dcapx?schema=public",
    });
  });
});
"""))

compose_text = compose_path.read_text()

replacements = {
    r'VAULT_ENABLED:\s*\$\{VAULT_ENABLED:-false\}': 'VAULT_ENABLED: ${VAULT_ENABLED_API_CONTAINER:-false}',
    r'VAULT_ADDR:\s*\$\{VAULT_ADDR:-\}': 'VAULT_ADDR: ${VAULT_ADDR_API_CONTAINER:-}',
    r'VAULT_MOUNT_PATH:\s*\$\{VAULT_MOUNT_PATH:-approle\}': 'VAULT_MOUNT_PATH: ${VAULT_MOUNT_PATH_API_CONTAINER:-approle}',
    r'VAULT_ROLE_ID:\s*\$\{VAULT_ROLE_ID:-\}': 'VAULT_ROLE_ID: ${VAULT_ROLE_ID_API_CONTAINER:-}',
    r'VAULT_SECRET_ID:\s*\$\{VAULT_SECRET_ID:-\}': 'VAULT_SECRET_ID: ${VAULT_SECRET_ID_API_CONTAINER:-}',
    r'VAULT_SECRET_ID_FILE:\s*\$\{VAULT_SECRET_ID_FILE:-\}': 'VAULT_SECRET_ID_FILE: ${VAULT_SECRET_ID_FILE_API_CONTAINER:-}',
    r'VAULT_SECRET_PATH:\s*\$\{VAULT_SECRET_PATH:-secret/data/dcapx/api\}': 'VAULT_SECRET_PATH: ${VAULT_SECRET_PATH_API_CONTAINER:-secret/data/dcapx/api-container}',
    r'VAULT_OVERRIDE_ENV:\s*\$\{VAULT_OVERRIDE_ENV:-false\}': 'VAULT_OVERRIDE_ENV: ${VAULT_OVERRIDE_ENV_API_CONTAINER:-true}',
}

for pattern, replacement in replacements.items():
    compose_text = re.sub(pattern, replacement, compose_text)

# Handle already-patched generic variants if they differ slightly.
compose_text = re.sub(
    r'VAULT_SECRET_PATH:\s*\$\{VAULT_SECRET_PATH:-secret/data/dcapx/api-container\}',
    'VAULT_SECRET_PATH: ${VAULT_SECRET_PATH_API_CONTAINER:-secret/data/dcapx/api-container}',
    compose_text,
)
compose_text = re.sub(
    r'VAULT_OVERRIDE_ENV:\s*\$\{VAULT_OVERRIDE_ENV:-true\}',
    'VAULT_OVERRIDE_ENV: ${VAULT_OVERRIDE_ENV_API_CONTAINER:-true}',
    compose_text,
)

# If some keys are still missing in the api environment block, insert them near EMAIL/RESEND area.
required_lines = [
    '        VAULT_ENABLED: ${VAULT_ENABLED_API_CONTAINER:-false}',
    '        VAULT_ADDR: ${VAULT_ADDR_API_CONTAINER:-}',
    '        VAULT_MOUNT_PATH: ${VAULT_MOUNT_PATH_API_CONTAINER:-approle}',
    '        VAULT_ROLE_ID: ${VAULT_ROLE_ID_API_CONTAINER:-}',
    '        VAULT_SECRET_ID: ${VAULT_SECRET_ID_API_CONTAINER:-}',
    '        VAULT_SECRET_ID_FILE: ${VAULT_SECRET_ID_FILE_API_CONTAINER:-}',
    '        VAULT_SECRET_PATH: ${VAULT_SECRET_PATH_API_CONTAINER:-secret/data/dcapx/api-container}',
    '        VAULT_OVERRIDE_ENV: ${VAULT_OVERRIDE_ENV_API_CONTAINER:-true}',
]

if 'VAULT_SECRET_PATH_API_CONTAINER' not in compose_text:
    anchor = '        RESEND_API_KEY: ${RESEND_API_KEY:-}'
    if anchor not in compose_text:
        raise SystemExit("Could not find compose environment anchor for Vault runtime-specific vars")
    insertion = "\n".join(required_lines) + "\n"
    compose_text = compose_text.replace(anchor, insertion + anchor, 1)

if 'VAULT_SECRET_PATH_API_CONTAINER' not in compose_text or 'VAULT_ENABLED_API_CONTAINER' not in compose_text:
    raise SystemExit("Could not patch docker-compose.yml with runtime-specific Vault metadata")

compose_path.write_text(compose_text)

print("Patched package.json, added .env.vault.host.example, added masked vault-context verification script + focused test, and updated docker-compose api Vault envs to runtime-specific *_API_CONTAINER settings.")
PY

echo "Resolved repo root: $ROOT"
echo "Runtime-specific Vault paths patch applied."
