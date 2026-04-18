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
