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
pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:auth:vault-bootstrap"] = "vitest run test/vault-bootstrap.test.ts"
scripts["test:middleware:ibac"] = "vitest run test/ibac.middleware.test.ts"
scripts["test:pass-b"] = "vitest run test/vault-bootstrap.test.ts test/ibac.middleware.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

vault_test = dedent("""
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { nodeVaultMock, clientMock } = vi.hoisted(() => {
  const client = {
    write: vi.fn(),
    read: vi.fn(),
    token: null as string | null,
    tokenRevokeSelf: vi.fn(),
  };

  return {
    nodeVaultMock: vi.fn(() => client),
    clientMock: client,
  };
});

vi.mock("node-vault", () => ({ default: nodeVaultMock }));

import {
  fetchSecretsFromVault,
  getVaultBootstrapConfig,
  isVaultEnabled,
} from "../src/lib/vault-client";
import { bootstrapSecrets } from "../src/lib/bootstrap-secrets";

const ORIGINAL_ENV = { ...process.env };
const tempFiles: string[] = [];

function restoreEnv() {
  for (const key of Object.keys(process.env)) {
    if (!(key in ORIGINAL_ENV)) {
      delete process.env[key];
    }
  }
  Object.assign(process.env, ORIGINAL_ENV);
}

function writeTempSecretIdFile(contents: string): string {
  const filePath = path.join(
    os.tmpdir(),
    `dcapx-vault-secret-${Date.now()}-${Math.random().toString(16).slice(2)}.txt`,
  );
  fs.writeFileSync(filePath, contents, "utf8");
  tempFiles.push(filePath);
  return filePath;
}

beforeEach(() => {
  vi.clearAllMocks();
  clientMock.token = null;

  delete process.env.VAULT_ENABLED;
  delete process.env.VAULT_ADDR;
  delete process.env.VAULT_ROLE_ID;
  delete process.env.VAULT_SECRET_ID;
  delete process.env.VAULT_SECRET_ID_FILE;
  delete process.env.VAULT_SECRET_PATH;
  delete process.env.VAULT_MOUNT_PATH;
  delete process.env.VAULT_OVERRIDE_ENV;
  delete process.env.JWT_SECRET;
  delete process.env.EXISTING_ONLY;
  delete process.env.EMPTY_VALUE;
  delete process.env.NEW_VALUE;
});

afterEach(() => {
  restoreEnv();
  while (tempFiles.length) {
    const filePath = tempFiles.pop()!;
    try {
      fs.unlinkSync(filePath);
    } catch {}
  }
  vi.restoreAllMocks();
});

describe("vault-client", () => {
  it("returns false when vault is disabled", () => {
    expect(isVaultEnabled()).toBe(false);
    expect(getVaultBootstrapConfig()).toBeNull();
  });

  it("loads the secret id from VAULT_SECRET_ID_FILE", () => {
    process.env.VAULT_ENABLED = "1";
    process.env.VAULT_ADDR = "http://vault:8200";
    process.env.VAULT_ROLE_ID = "role-123";
    process.env.VAULT_SECRET_ID_FILE = writeTempSecretIdFile("secret-from-file");
    process.env.VAULT_SECRET_PATH = "secret/data/dcapx/custom";

    const config = getVaultBootstrapConfig();

    expect(config).toEqual({
      enabled: true,
      addr: "http://vault:8200",
      mountPath: "approle",
      roleId: "role-123",
      secretId: "secret-from-file",
      secretPath: "secret/data/dcapx/custom",
    });
  });

  it("fetches kv-v2 secrets and revokes the token afterward", async () => {
    process.env.VAULT_ENABLED = "1";
    process.env.VAULT_ADDR = "http://vault:8200";
    process.env.VAULT_ROLE_ID = "role-123";
    process.env.VAULT_SECRET_ID_FILE = writeTempSecretIdFile("secret-from-file");
    process.env.VAULT_SECRET_PATH = "secret/data/dcapx/api";

    clientMock.write.mockResolvedValue({
      auth: { client_token: "token-abc" },
    });
    clientMock.read.mockResolvedValue({
      data: {
        data: {
          JWT_SECRET: "jwt-from-vault",
          NUMERIC_VALUE: 42,
          JSON_VALUE: { ok: true },
        },
      },
    });
    clientMock.tokenRevokeSelf.mockResolvedValue(undefined);

    const result = await fetchSecretsFromVault();

    expect(nodeVaultMock).toHaveBeenCalledWith({
      endpoint: "http://vault:8200",
      apiVersion: "v1",
    });
    expect(clientMock.write).toHaveBeenCalledWith("auth/approle/login", {
      role_id: "role-123",
      secret_id: "secret-from-file",
    });
    expect(clientMock.read).toHaveBeenCalledWith("secret/data/dcapx/api");
    expect(clientMock.tokenRevokeSelf).toHaveBeenCalledTimes(1);
    expect(result).toEqual({
      JWT_SECRET: "jwt-from-vault",
      NUMERIC_VALUE: "42",
      JSON_VALUE: '{"ok":true}',
    });
  });

  it("revokes the token even when the vault read fails", async () => {
    process.env.VAULT_ENABLED = "1";
    process.env.VAULT_ADDR = "http://vault:8200";
    process.env.VAULT_ROLE_ID = "role-123";
    process.env.VAULT_SECRET_ID = "secret-inline";
    process.env.VAULT_SECRET_PATH = "secret/data/dcapx/api";

    clientMock.write.mockResolvedValue({
      auth: { client_token: "token-abc" },
    });
    clientMock.read.mockRejectedValue(new Error("vault read failed"));
    clientMock.tokenRevokeSelf.mockResolvedValue(undefined);

    await expect(fetchSecretsFromVault()).rejects.toThrow("vault read failed");
    expect(clientMock.tokenRevokeSelf).toHaveBeenCalledTimes(1);
  });
});

describe("bootstrapSecrets", () => {
  it("skips reserved VAULT_* keys and preserves existing values when override is disabled", async () => {
    process.env.VAULT_ENABLED = "1";
    process.env.VAULT_ADDR = "http://vault:8200";
    process.env.VAULT_ROLE_ID = "role-123";
    process.env.VAULT_SECRET_ID = "secret-inline";
    process.env.VAULT_SECRET_PATH = "secret/data/dcapx/api";

    process.env.JWT_SECRET = "keep-existing";
    process.env.EXISTING_ONLY = "keep-this";
    process.env.EMPTY_VALUE = "";

    clientMock.write.mockResolvedValue({
      auth: { client_token: "token-abc" },
    });
    clientMock.read.mockResolvedValue({
      data: {
        data: {
          VAULT_ADDR: "http://evil:8200",
          JWT_SECRET: "replace-me",
          EXISTING_ONLY: "replace-existing",
          EMPTY_VALUE: "fill-empty",
          NEW_VALUE: "new-from-vault",
        },
      },
    });
    clientMock.tokenRevokeSelf.mockResolvedValue(undefined);

    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await bootstrapSecrets();

    expect(process.env.VAULT_ADDR).toBe("http://vault:8200");
    expect(process.env.JWT_SECRET).toBe("keep-existing");
    expect(process.env.EXISTING_ONLY).toBe("keep-this");
    expect(process.env.EMPTY_VALUE).toBe("fill-empty");
    expect(process.env.NEW_VALUE).toBe("new-from-vault");
    expect(logSpy).toHaveBeenCalledWith("[vault] loaded 2 secret values from secret/data/dcapx/api");
  });

  it("overrides existing values when VAULT_OVERRIDE_ENV is enabled", async () => {
    process.env.VAULT_ENABLED = "1";
    process.env.VAULT_ADDR = "http://vault:8200";
    process.env.VAULT_ROLE_ID = "role-123";
    process.env.VAULT_SECRET_ID = "secret-inline";
    process.env.VAULT_SECRET_PATH = "secret/data/dcapx/api";
    process.env.VAULT_OVERRIDE_ENV = "1";

    process.env.JWT_SECRET = "keep-existing";

    clientMock.write.mockResolvedValue({
      auth: { client_token: "token-abc" },
    });
    clientMock.read.mockResolvedValue({
      data: {
        data: {
          JWT_SECRET: "override-from-vault",
        },
      },
    });
    clientMock.tokenRevokeSelf.mockResolvedValue(undefined);

    await bootstrapSecrets();

    expect(process.env.JWT_SECRET).toBe("override-from-vault");
  });
});
""").lstrip()

test_path = root / "apps/api/test/vault-bootstrap.test.ts"
test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(vault_test)

print("Patched package.json and rewrote apps/api/test/vault-bootstrap.test.ts for Pass B.")
PY

echo "Resolved repo root: $ROOT"
echo "Pass B patch applied."
