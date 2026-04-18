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
script_path = root / "apps/api/src/scripts/vault-exec.ts"
test_path = root / "apps/api/test/vault-exec.script.test.ts"
compose_path = root / "docker-compose.yml"

for p in [pkg_path, compose_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["vault:exec"] = "node dist/scripts/vault-exec.js"
scripts["prisma:migrate:vault"] = "pnpm build && node dist/scripts/vault-exec.js pnpm prisma migrate deploy"
scripts["start:vault"] = "pnpm build && node dist/scripts/vault-exec.js node dist/server.js"
scripts["boot:vault"] = "node dist/scripts/vault-exec.js sh -lc \"pnpm prisma migrate deploy && node dist/server.js\""
scripts["test:vault-exec"] = "vitest run test/vault-exec.script.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

script_path.parent.mkdir(parents=True, exist_ok=True)
script_path.write_text(dedent("""\
import "dotenv/config";
import { spawn, type SpawnOptions } from "node:child_process";

import { bootstrapSecrets } from "../lib/bootstrap-secrets";

export async function runVaultExec(
  argv: string[] = process.argv.slice(2),
  spawnImpl: typeof spawn = spawn,
  env: NodeJS.ProcessEnv = process.env,
): Promise<void> {
  const [command, ...args] = argv;
  if (!command) {
    throw new Error("No command provided to vault-exec");
  }

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

test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(dedent("""\
import { beforeEach, describe, expect, it, vi } from "vitest";

const { bootstrapSecrets } = vi.hoisted(() => ({
  bootstrapSecrets: vi.fn(),
}));

vi.mock("../src/lib/bootstrap-secrets", () => ({
  bootstrapSecrets,
}));

import { runVaultExec } from "../src/scripts/vault-exec";

function createChild(exitCode: number) {
  return {
    once(event: string, handler: (...args: any[]) => void) {
      if (event === "exit") {
        setTimeout(() => handler(exitCode), 0);
      }
      return this;
    },
  };
}

describe("vault-exec script", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    bootstrapSecrets.mockResolvedValue(undefined);
  });

  it("bootstraps secrets before spawning a child command", async () => {
    const spawnMock = vi.fn().mockReturnValue(createChild(0));

    await runVaultExec(
      ["pnpm", "prisma", "migrate", "deploy"],
      spawnMock as any,
      { DATABASE_URL: "vault" } as any,
    );

    expect(bootstrapSecrets).toHaveBeenCalledTimes(1);
    expect(spawnMock).toHaveBeenCalledTimes(1);
    expect(spawnMock).toHaveBeenCalledWith(
      "pnpm",
      ["prisma", "migrate", "deploy"],
      expect.objectContaining({
        stdio: "inherit",
        env: { DATABASE_URL: "vault" },
        shell: false,
      }),
    );
  });

  it("throws when no command is provided", async () => {
    await expect(runVaultExec([], vi.fn() as any)).rejects.toThrow(/No command provided/);
    expect(bootstrapSecrets).not.toHaveBeenCalled();
  });

  it("rejects when the child exits non-zero", async () => {
    const spawnMock = vi.fn().mockReturnValue(createChild(1));

    await expect(runVaultExec(["pnpm", "prisma", "migrate", "deploy"], spawnMock as any)).rejects.toThrow(
      /child exited with code 1/,
    );
  });
});
"""))

compose_text = compose_path.read_text()
if 'pnpm boot:vault' not in compose_text:
    patterns = [
        (
            'command: ["sh", "-lc", "pnpm prisma migrate deploy && pnpm start"]',
            'command: ["sh", "-lc", "pnpm boot:vault"]',
        ),
        (
            'command: ["sh", "-lc", "pnpm prisma migrate deploy && node dist/server.js"]',
            'command: ["sh", "-lc", "pnpm boot:vault"]',
        ),
        (
            'command: ["sh", "-lc", "pnpm prisma migrate deploy && pnpm start"]',
            'command: ["sh", "-lc", "pnpm boot:vault"]',
        ),
    ]
    replaced = False
    for old, new in patterns:
        if old in compose_text:
            compose_text = compose_text.replace(old, new, 1)
            replaced = True
            break
    if not replaced:
        compose_text = re.sub(
            r'(?ms)(^\s*api:\n(?:^\s{4,}.*\n)*?^\s{4}command:\s*\[.*?\]\s*$)',
            lambda m: re.sub(r'^\s{4}command:\s*\[.*?\]\s*$', '    command: ["sh", "-lc", "pnpm boot:vault"]', m.group(1), flags=re.M),
            compose_text,
            count=1,
        )
    if 'pnpm boot:vault' not in compose_text:
        raise SystemExit("Could not patch docker-compose api command to use pnpm boot:vault")

compose_path.write_text(compose_text)

print("Patched package.json, added src/scripts/vault-exec.ts + focused test, and switched docker-compose api startup to pnpm boot:vault for Vault-first migrations.")
PY

echo "Resolved repo root: $ROOT"
echo "Vault-first migration patch applied."
