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
    fs.writeFileSync(path.join(repoRoot, "docker-compose.yml"), "services:\n");
    fs.writeFileSync(
      path.join(repoRoot, ".env.vault.host"),
      "VAULT_ENABLED=true\nVAULT_SECRET_PATH=secret/data/dcapx/api-host\n",
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
    fs.writeFileSync(path.join(repoRoot, "pnpm-workspace.yaml"), "packages:\n  - apps/*\n");
    fs.writeFileSync(
      path.join(repoRoot, ".env.vault.host"),
      [
        "VAULT_ENABLED=true",
        "VAULT_ADDR=http://127.0.0.1:8200",
        "VAULT_ROLE_ID=test-role-id",
        "VAULT_SECRET_ID_FILE=/tmp/test.secret-id",
        "VAULT_SECRET_PATH=secret/data/dcapx/api-host",
        "VAULT_OVERRIDE_ENV=true",
      ].join("\n") + "\n",
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
    fs.writeFileSync(path.join(repoRoot, "docker-compose.yml"), "services:\n");
    fs.writeFileSync(explicitFile, "VAULT_ENABLED=true\nVAULT_SECRET_PATH=secret/data/dcapx/api-host\n");

    process.chdir(apiDir);
    process.env.VAULT_BOOTSTRAP_FILE = explicitFile;

    expect(resolveVaultBootstrapFile(process.cwd(), path.join(apiDir, "dist", "scripts"))).toBe(
      explicitFile,
    );
  });
});
