#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-}"
if [[ -z "$REPO_ROOT" ]]; then
  echo "Usage: $0 /path/to/DCapXP1" >&2
  exit 1
fi
if [[ ! -d "$REPO_ROOT" ]]; then
  echo "Repo path not found: $REPO_ROOT" >&2
  exit 1
fi

cd "$REPO_ROOT"

need_file() {
  local path="$1"
  [[ -f "$path" ]] || { echo "Missing required file: $path" >&2; exit 1; }
}

need_file "apps/api/package.json"
need_file "apps/api/src/server.ts"
need_file "docker-compose.yml"
need_file "docker-compose.prod.yml"
need_file ".env.example"

python3 <<'PY'
from pathlib import Path
import json

path = Path('apps/api/package.json')
data = json.loads(path.read_text())
deps = data.setdefault('dependencies', {})
# Latest npm release visible at time of writing is 0.12.0; pin to that major/minor.
deps['node-vault'] = '^0.12.0'
path.write_text(json.dumps(data, indent=2) + '\n')
PY

mkdir -p apps/api/src/lib apps/api/src/types

cat > apps/api/src/types/node-vault.d.ts <<'EOF_TS'
declare module "node-vault" {
  export interface VaultClient {
    token?: string;
    read(path: string): Promise<any>;
    write(path: string, data?: Record<string, unknown>): Promise<any>;
    tokenRevokeSelf?(): Promise<any>;
  }

  export interface VaultOptions {
    endpoint: string;
    apiVersion?: string;
    token?: string;
    [key: string]: unknown;
  }

  export default function nodeVault(options?: VaultOptions): VaultClient;
}
EOF_TS

cat > apps/api/src/lib/vault-client.ts <<'EOF_TS'
import nodeVault from "node-vault";

export type VaultSecretMap = Record<string, string>;

export interface VaultBootstrapConfig {
  enabled: boolean;
  addr: string;
  mountPath: string;
  roleId: string;
  secretId: string;
  secretPath: string;
}

function truthy(value: string | undefined): boolean {
  if (!value) return false;
  return ["1", "true", "yes", "on"].includes(value.trim().toLowerCase());
}

function requireEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}

function readSecretId(): string {
  const filePath = process.env.VAULT_SECRET_ID_FILE?.trim();
  if (filePath) {
    const fs = require("node:fs") as typeof import("node:fs");
    const value = fs.readFileSync(filePath, "utf8").trim();
    if (!value) {
      throw new Error(`VAULT_SECRET_ID_FILE is empty: ${filePath}`);
    }
    return value;
  }
  return requireEnv("VAULT_SECRET_ID");
}

function normalizeSecretValue(value: unknown): string {
  if (typeof value === "string") return value;
  return JSON.stringify(value);
}

function extractSecretMap(payload: any): VaultSecretMap {
  const kvV2 = payload?.data?.data;
  const kvV1 = payload?.data;
  const source = kvV2 && typeof kvV2 === "object" ? kvV2 : kvV1 && typeof kvV1 === "object" ? kvV1 : null;
  if (!source || typeof source !== "object") {
    return {};
  }

  const result: VaultSecretMap = {};
  for (const [key, value] of Object.entries(source)) {
    if (value === undefined || value === null) continue;
    result[key] = normalizeSecretValue(value);
  }
  return result;
}

export function isVaultEnabled(): boolean {
  return truthy(process.env.VAULT_ENABLED);
}

export function getVaultBootstrapConfig(): VaultBootstrapConfig | null {
  if (!isVaultEnabled()) {
    return null;
  }

  return {
    enabled: true,
    addr: requireEnv("VAULT_ADDR"),
    mountPath: process.env.VAULT_MOUNT_PATH?.trim() || "approle",
    roleId: requireEnv("VAULT_ROLE_ID"),
    secretId: readSecretId(),
    secretPath: process.env.VAULT_SECRET_PATH?.trim() || "secret/data/dcapx/api",
  };
}

export async function fetchSecretsFromVault(): Promise<VaultSecretMap> {
  const config = getVaultBootstrapConfig();
  if (!config) {
    return {};
  }

  const client = nodeVault({
    endpoint: config.addr,
    apiVersion: "v1",
  });

  const login = await client.write(`auth/${config.mountPath}/login`, {
    role_id: config.roleId,
    secret_id: config.secretId,
  });

  const token = login?.auth?.client_token;
  if (!token || typeof token !== "string") {
    throw new Error("Vault AppRole login did not return a client token");
  }

  client.token = token;

  try {
    const secret = await client.read(config.secretPath);
    const values = extractSecretMap(secret);
    if (Object.keys(values).length === 0) {
      throw new Error(`Vault secret path returned no key/value pairs: ${config.secretPath}`);
    }
    return values;
  } finally {
    try {
      if (typeof client.tokenRevokeSelf === "function") {
        await client.tokenRevokeSelf();
      }
    } catch {
      // Best-effort revoke; let the short-lived token expire if revoke fails.
    }
  }
}
EOF_TS

cat > apps/api/src/lib/bootstrap-secrets.ts <<'EOF_TS'
import { fetchSecretsFromVault, isVaultEnabled } from "./vault-client";

function truthy(value: string | undefined): boolean {
  if (!value) return false;
  return ["1", "true", "yes", "on"].includes(value.trim().toLowerCase());
}

const RESERVED_KEYS = new Set([
  "VAULT_ENABLED",
  "VAULT_ADDR",
  "VAULT_ROLE_ID",
  "VAULT_SECRET_ID",
  "VAULT_SECRET_ID_FILE",
  "VAULT_SECRET_PATH",
  "VAULT_MOUNT_PATH",
  "VAULT_OVERRIDE_ENV",
]);

export async function bootstrapSecrets(): Promise<void> {
  if (!isVaultEnabled()) {
    console.log("[vault] bootstrap disabled");
    return;
  }

  const secrets = await fetchSecretsFromVault();
  const overrideExisting = truthy(process.env.VAULT_OVERRIDE_ENV);
  let applied = 0;

  for (const [key, value] of Object.entries(secrets)) {
    if (RESERVED_KEYS.has(key)) continue;
    const current = process.env[key];
    if (overrideExisting || current === undefined || current === "") {
      process.env[key] = value;
      applied += 1;
    }
  }

  const path = process.env.VAULT_SECRET_PATH ?? "secret/data/dcapx/api";
  console.log(`[vault] loaded ${applied} secret values from ${path}`);
}
EOF_TS

cat > apps/api/src/server.ts <<'EOF_TS'
import "dotenv/config";
import type { Server } from "http";
import { bootstrapSecrets } from "./lib/bootstrap-secrets";

const PORT = Number(process.env.API_PORT ?? process.env.PORT ?? 4010);
const IS_PRODUCTION = process.env.NODE_ENV === "production";

let server: Server | null = null;
let shuttingDown = false;
let prismaClient: { $disconnect(): Promise<void> } | null = null;

function requireEnv(name: string): void {
  if (!process.env[name]?.trim()) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
}

function validateEnv(): void {
  requireEnv("DATABASE_URL");
  requireEnv("JWT_SECRET");
  requireEnv("OTP_HMAC_SECRET");
  if (IS_PRODUCTION) {
    requireEnv("APP_BASE_URL");
    requireEnv("APP_CORS_ORIGINS");
    requireEnv("EMAIL_FROM");
  }
}

async function shutdown(signal: string): Promise<void> {
  if (shuttingDown) {
    return;
  }
  shuttingDown = true;
  console.log(`[server] received ${signal}, shutting down`);

  const closeServer = new Promise<void>((resolve) => {
    if (!server) {
      resolve();
      return;
    }
    server.close(() => resolve());
  });

  const forceExitTimer = setTimeout(() => {
    console.error("[server] forced shutdown after timeout");
    process.exit(1);
  }, 30_000);

  try {
    await closeServer;
    if (prismaClient) {
      await prismaClient.$disconnect();
    }
    clearTimeout(forceExitTimer);
    process.exit(0);
  } catch (error) {
    clearTimeout(forceExitTimer);
    console.error("[server] shutdown failed", error);
    process.exit(1);
  }
}

async function main(): Promise<void> {
  await bootstrapSecrets();
  validateEnv();

  const [{ default: app }, { prisma }] = await Promise.all([
    import("./app"),
    import("./lib/prisma"),
  ]);

  prismaClient = prisma;

  server = app.listen(PORT, () => {
    console.log(`api listening on ${PORT}`);
  });
}

void main().catch((error) => {
  console.error("[server] startup failed", error);
  process.exit(1);
});

process.on("SIGTERM", () => {
  void shutdown("SIGTERM");
});
process.on("SIGINT", () => {
  void shutdown("SIGINT");
});
process.on("unhandledRejection", (error) => {
  console.error("unhandledRejection", error);
});
process.on("uncaughtException", (error) => {
  console.error("uncaughtException", error);
  void shutdown("uncaughtException");
});
EOF_TS

cat > .env.example <<'EOF_ENV'
# --- Postgres ---
POSTGRES_USER=dcapx
POSTGRES_PASSWORD=change-me
POSTGRES_DB=dcapx

# --- App secrets (used directly when Vault is disabled) ---
ADMIN_KEY=change-me
JWT_SECRET=change-me
OTP_HMAC_SECRET=change-me
RESEND_API_KEY=
EMAIL_FROM=DCapX <no-reply@example.com>

# --- App settings ---
NODE_ENV=development
APP_BASE_URL=http://localhost:3000
APP_CORS_ORIGINS=http://localhost:3000
EMAIL_PROVIDER=console
REDIS_URL=redis://redis:6379

# --- Database connection string ---
# Prisma migrations run before server bootstrap in the current Docker flow,
# so DATABASE_URL still needs to be available in the container environment.
DATABASE_URL=postgresql://dcapx:change-me@pg:5432/dcapx?schema=public

# --- Optional Vault bootstrap (AppRole) ---
VAULT_ENABLED=false
VAULT_ADDR=http://vault:8200
VAULT_MOUNT_PATH=approle
VAULT_ROLE_ID=
# Prefer VAULT_SECRET_ID_FILE in Docker/production. Keep VAULT_SECRET_ID for local dev only.
VAULT_SECRET_ID=
VAULT_SECRET_ID_FILE=
VAULT_SECRET_PATH=secret/data/dcapx/api
# When true, Vault-loaded values replace existing non-empty env vars.
VAULT_OVERRIDE_ENV=false
EOF_ENV

python3 <<'PY'
from pathlib import Path
import re

compose_files = [Path('docker-compose.yml'), Path('docker-compose.prod.yml')]

api_env_lines = [
    '      VAULT_ENABLED: ${VAULT_ENABLED:-false}',
    '      VAULT_ADDR: ${VAULT_ADDR:-}',
    '      VAULT_MOUNT_PATH: ${VAULT_MOUNT_PATH:-approle}',
    '      VAULT_ROLE_ID: ${VAULT_ROLE_ID:-}',
    '      VAULT_SECRET_ID: ${VAULT_SECRET_ID:-}',
    '      VAULT_SECRET_ID_FILE: ${VAULT_SECRET_ID_FILE:-}',
    '      VAULT_SECRET_PATH: ${VAULT_SECRET_PATH:-secret/data/dcapx/api}',
    '      VAULT_OVERRIDE_ENV: ${VAULT_OVERRIDE_ENV:-false}',
    '      RESEND_API_KEY: ${RESEND_API_KEY:-}',
]

replacements = {
    r'^(\s*ADMIN_KEY:\s*).*$': r'\1${ADMIN_KEY:-}',
    r'^(\s*JWT_SECRET:\s*).*$': r'\1${JWT_SECRET:-}',
    r'^(\s*OTP_HMAC_SECRET:\s*).*$': r'\1${OTP_HMAC_SECRET:-}',
    r'^(\s*DATABASE_URL:\s*).*$': r'\1${DATABASE_URL}',
    r'^(\s*REDIS_URL:\s*).*$': r'\1${REDIS_URL:-redis://redis:6379}',
    r'^(\s*EMAIL_PROVIDER:\s*).*$': r'\1${EMAIL_PROVIDER:-console}',
    r'^(\s*EMAIL_FROM:\s*).*$': r'\1${EMAIL_FROM:-DCapX <no-reply@dcapitalx.local>}',
    r'^(\s*APP_BASE_URL:\s*).*$': r'\1${APP_BASE_URL:-http://localhost:3000}',
    r'^(\s*APP_CORS_ORIGINS:\s*).*$': r'\1${APP_CORS_ORIGINS:-http://localhost:3000}',
    r'^(\s*NODE_ENV:\s*).*$': r'\1${NODE_ENV:-production}',
}

for path in compose_files:
    text = path.read_text()
    if '\n' not in text:
        # Best-effort bail out on minified files; user can reformat if needed.
        continue

    for pattern, replacement in replacements.items():
        text = re.sub(pattern, replacement, text, flags=re.MULTILINE)

    text = re.sub(r'^\s*ENABLE_BOT_FARM:.*\n?', '', text, flags=re.MULTILINE)

    if 'VAULT_ENABLED:' not in text:
        anchor_match = re.search(r'^(\s*EMAIL_FROM:.*\n)', text, flags=re.MULTILINE)
        if anchor_match:
            insertion = ''.join(line + '\n' for line in api_env_lines)
            text = text[:anchor_match.end()] + insertion + text[anchor_match.end():]
        else:
            env_match = re.search(r'^(\s*environment:\s*\n)', text, flags=re.MULTILINE)
            if env_match:
                insertion = ''.join(line + '\n' for line in api_env_lines)
                text = text[:env_match.end()] + insertion + text[env_match.end():]

    path.write_text(text)
PY

echo "Vault bootstrap patch applied."
echo "Next recommended commands:"
echo "  cd $REPO_ROOT"
echo "  pnpm install"
echo "  pnpm --filter api build"
echo "  docker compose config"
