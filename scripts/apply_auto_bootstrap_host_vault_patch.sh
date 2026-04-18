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
import sys
from textwrap import dedent

root = Path(sys.argv[1])

pkg_path = root / "apps/api/package.json"
helper_path = root / "apps/api/src/scripts/vault-bootstrap-env.ts"
vault_exec_path = root / "apps/api/src/scripts/vault-exec.ts"
print_ctx_path = root / "apps/api/src/scripts/print-vault-context.ts"
test_path = root / "apps/api/test/vault-auto-bootstrap.test.ts"

for p in [pkg_path, vault_exec_path, print_ctx_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:vault-auto-bootstrap"] = "vitest run test/vault-auto-bootstrap.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

helper_path.parent.mkdir(parents=True, exist_ok=True)
helper_path.write_text(dedent("""\
import fs from "node:fs";
import path from "node:path";

import * as dotenv from "dotenv";

const HOST_BOOTSTRAP_FILENAME = ".env.vault.host";

function fileExists(filePath: string): boolean {
  try {
    return fs.existsSync(filePath);
  } catch {
    return false;
  }
}

export function findRepoRoot(startDir: string): string | null {
  let current = path.resolve(startDir);

  while (true) {
    const markers = [
      path.join(current, "pnpm-workspace.yaml"),
      path.join(current, "docker-compose.yml"),
      path.join(current, ".git"),
    ];

    if (markers.some(fileExists)) {
      return current;
    }

    const parent = path.dirname(current);
    if (parent === current) {
      return null;
    }
    current = parent;
  }
}

export function resolveVaultBootstrapFile(
  cwd: string = process.cwd(),
  scriptDir: string = __dirname,
  explicitPath?: string | null,
): string | null {
  const envOverride = explicitPath ?? process.env.VAULT_BOOTSTRAP_FILE ?? null;
  if (envOverride) {
    const resolved = path.resolve(envOverride);
    return fileExists(resolved) ? resolved : null;
  }

  const candidates = new Set<string>();

  candidates.add(path.resolve(cwd, HOST_BOOTSTRAP_FILENAME));

  const cwdRoot = findRepoRoot(cwd);
  if (cwdRoot) {
    candidates.add(path.join(cwdRoot, HOST_BOOTSTRAP_FILENAME));
  }

  const scriptRoot = findRepoRoot(scriptDir);
  if (scriptRoot) {
    candidates.add(path.join(scriptRoot, HOST_BOOTSTRAP_FILENAME));
  }

  for (const candidate of candidates) {
    if (fileExists(candidate)) {
      return candidate;
    }
  }

  return null;
}

export function loadVaultBootstrapEnv(
  cwd: string = process.cwd(),
  scriptDir: string = __dirname,
): string | null {
  const resolved = resolveVaultBootstrapFile(cwd, scriptDir);
  if (!resolved) {
    return null;
  }

  dotenv.config({
    path: resolved,
    override: true,
  });

  return resolved;
}
"""))

vault_exec_path.write_text(dedent("""\
import * as dotenv from "dotenv";
import { spawn, type SpawnOptions } from "node:child_process";

import { bootstrapSecrets } from "../lib/bootstrap-secrets";
import { loadVaultBootstrapEnv } from "./vault-bootstrap-env";

dotenv.config();

export async function runVaultExec(
  argv: string[] = process.argv.slice(2),
  spawnImpl: typeof spawn = spawn,
  env: NodeJS.ProcessEnv = process.env,
): Promise<void> {
  const [command, ...args] = argv;
  if (!command) {
    throw new Error("No command provided to vault-exec");
  }

  loadVaultBootstrapEnv(process.cwd(), __dirname);
  await bootstrapSecrets();

  await new Promise<void>((resolve, reject) => {
    const options: SpawnOptions = {
      stdio: "inherit",
      env,
      shell: false,
    };

    const child = spawnImpl(command, args, options);

    child.once("error", (error) => {
      reject(error);
    });

    child.once("exit", (code) => {
      if (code === 0) {
        resolve();
        return;
      }
      reject(new Error(`vault-exec child exited with code ${String(code)}`));
    });
  });
}

async function main(): Promise<void> {
  try {
    await runVaultExec();
  } catch (error) {
    console.error("[vault-exec] failed", error);
    process.exit(1);
  }
}

if (require.main === module) {
  void main();
}
"""))

print_ctx_path.write_text(dedent("""\
import * as dotenv from "dotenv";

import { bootstrapSecrets } from "../lib/bootstrap-secrets";
import { loadVaultBootstrapEnv, resolveVaultBootstrapFile } from "./vault-bootstrap-env";

dotenv.config();

export function maskDatabaseUrl(url?: string | null): string | null {
  if (!url) return null;
  return url.replace(/:([^:@/]+)@/, ":****@");
}

export async function collectVaultContext(
  env: NodeJS.ProcessEnv = process.env,
): Promise<Record<string, unknown>> {
  const bootstrapFile = loadVaultBootstrapEnv(process.cwd(), __dirname);
  await bootstrapSecrets();

  return {
    bootstrapFile,
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
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  findRepoRoot,
  loadVaultBootstrapEnv,
  resolveVaultBootstrapFile,
} from "../src/scripts/vault-bootstrap-env";

describe("vault auto-bootstrap host env", () => {
  const originalCwd = process.cwd();
  const originalEnv = { ...process.env };
  let tempRoot = "";

  beforeEach(() => {
    tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "dcapx-vault-bootstrap-"));
    process.env = { ...originalEnv };
  });

  afterEach(() => {
    process.chdir(originalCwd);
    process.env = { ...originalEnv };
    fs.rmSync(tempRoot, { recursive: true, force: true });
  });

  it("finds the repo root and resolves .env.vault.host from repo root automatically", () => {
    const repoRoot = path.join(tempRoot, "repo");
    const apiDir = path.join(repoRoot, "apps", "api");
    fs.mkdirSync(apiDir, { recursive: true });
    fs.writeFileSync(path.join(repoRoot, "docker-compose.yml"), "services:\\n");
    fs.writeFileSync(
      path.join(repoRoot, ".env.vault.host"),
      "VAULT_ENABLED=true\\nVAULT_SECRET_PATH=secret/data/dcapx/api-host\\n",
    );

    process.chdir(apiDir);

    expect(findRepoRoot(process.cwd())).toBe(repoRoot);
    expect(resolveVaultBootstrapFile(process.cwd(), path.join(apiDir, "dist", "scripts"))).toBe(
      path.join(repoRoot, ".env.vault.host"),
    );
  });

  it("loads host bootstrap values without manual source when repo-root file exists", () => {
    const repoRoot = path.join(tempRoot, "repo");
    const apiDir = path.join(repoRoot, "apps", "api");
    fs.mkdirSync(apiDir, { recursive: true });
    fs.writeFileSync(path.join(repoRoot, "pnpm-workspace.yaml"), "packages:\\n  - apps/*\\n");
    fs.writeFileSync(
      path.join(repoRoot, ".env.vault.host"),
      [
        "VAULT_ENABLED=true",
        "VAULT_ADDR=http://127.0.0.1:8200",
        "VAULT_ROLE_ID=test-role-id",
        "VAULT_SECRET_ID_FILE=/tmp/test.secret-id",
        "VAULT_SECRET_PATH=secret/data/dcapx/api-host",
        "VAULT_OVERRIDE_ENV=true",
      ].join("\\n") + "\\n",
    );

    process.chdir(apiDir);

    const loaded = loadVaultBootstrapEnv(process.cwd(), path.join(apiDir, "dist", "scripts"));

    expect(loaded).toBe(path.join(repoRoot, ".env.vault.host"));
    expect(process.env.VAULT_ENABLED).toBe("true");
    expect(process.env.VAULT_ROLE_ID).toBe("test-role-id");
    expect(process.env.VAULT_SECRET_PATH).toBe("secret/data/dcapx/api-host");
  });

  it("prefers VAULT_BOOTSTRAP_FILE when explicitly provided", () => {
    const repoRoot = path.join(tempRoot, "repo");
    const apiDir = path.join(repoRoot, "apps", "api");
    const explicitFile = path.join(tempRoot, "custom.host.env");
    fs.mkdirSync(apiDir, { recursive: true });
    fs.writeFileSync(path.join(repoRoot, "docker-compose.yml"), "services:\\n");
    fs.writeFileSync(explicitFile, "VAULT_ENABLED=true\\nVAULT_SECRET_PATH=secret/data/dcapx/api-host\\n");

    process.chdir(apiDir);
    process.env.VAULT_BOOTSTRAP_FILE = explicitFile;

    expect(resolveVaultBootstrapFile(process.cwd(), path.join(apiDir, "dist", "scripts"))).toBe(
      explicitFile,
    );
  });
});
"""))

print("Patched package.json, added vault-bootstrap-env.ts auto-discovery helper, and rewrote vault-exec.ts + print-vault-context.ts to auto-load repo-root .env.vault.host without manual source, with focused tests.")
PY

echo "Resolved repo root: $ROOT"
echo "Auto-bootstrap host Vault patch applied."
