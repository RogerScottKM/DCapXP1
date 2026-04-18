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
