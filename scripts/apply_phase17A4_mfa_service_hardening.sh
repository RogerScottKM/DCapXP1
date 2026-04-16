#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${1:-}" ]]; then
  ROOT="$1"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import re
import sys
from textwrap import dedent

root = Path(sys.argv[1]).resolve()

pkg_path = root / "apps/api/package.json"
mfa_path = root / "apps/api/src/modules/auth/mfa.service.ts"
test_path = root / "apps/api/test/mfa.service.test.ts"

if not pkg_path.exists():
    raise SystemExit(f"Missing package.json: {pkg_path}")
if not mfa_path.exists():
    raise SystemExit(f"Missing mfa.service.ts: {mfa_path}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:auth:mfa-service"] = "vitest run test/mfa.service.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

mfa_src = mfa_path.read_text()

old_func_pattern = re.compile(
    r'private generateRecoveryCode\(\): string \{\s*const raw = crypto\s*\.randomBytes\(8\)\s*\.toString\("base64url"\)\s*\.replace\(/\[\^A-Za-z0-9\]/g, ""\)\s*\.toUpperCase\(\)\s*\.slice\(0, 12\);\s*return `\$\{raw\.slice\(0, 4\)\}-\$\{raw\.slice\(4, 8\)\}-\$\{raw\.slice\(8, 12\)\}`;\s*\}',
    re.DOTALL,
)

new_func = dedent('''
  private generateRecoveryCode(): string {
    let raw = "";
    while (raw.length < 12) {
      raw += crypto
        .randomBytes(8)
        .toString("base64url")
        .replace(/[^A-Za-z0-9]/g, "")
        .toUpperCase();
    }
    raw = raw.slice(0, 12);
    return `${raw.slice(0, 4)}-${raw.slice(4, 8)}-${raw.slice(8, 12)}`;
  }
''').strip()

if 'while (raw.length < 12)' not in mfa_src:
    mfa_src, count = old_func_pattern.subn(new_func, mfa_src, count=1)
    if count == 0:
        raise SystemExit('Could not patch generateRecoveryCode() in mfa.service.ts')
    mfa_path.write_text(mfa_src)


test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(dedent('''
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const {
  prismaMock,
  recordSecurityAudit,
  authenticatorMock,
} = vi.hoisted(() => ({
  prismaMock: {
    user: { findUnique: vi.fn() },
    mfaFactor: {
      findFirst: vi.fn(),
      updateMany: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
    },
    mfaRecoveryCode: {
      findFirst: vi.fn(),
      deleteMany: vi.fn(),
      createMany: vi.fn(),
      update: vi.fn(),
    },
    session: {
      update: vi.fn(),
      updateMany: vi.fn(),
    },
    $transaction: vi.fn(),
  },
  recordSecurityAudit: vi.fn(),
  authenticatorMock: {
    generateSecret: vi.fn(() => "JBSWY3DPEHPK3PXP"),
    check: vi.fn(),
    keyuri: vi.fn((accountName: string, issuer: string, secret: string) =>
      `otpauth://totp/${issuer}:${accountName}?secret=${secret}&issuer=${issuer}`,
    ),
    options: {},
  },
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/service/security-audit", () => ({ recordSecurityAudit }));
vi.mock("otplib", () => ({ authenticator: authenticatorMock }));

import { mfaService } from "../src/modules/auth/mfa.service";

const ORIGINAL_ENV = { ...process.env };

function restoreEnv() {
  for (const key of Object.keys(process.env)) {
    if (!(key in ORIGINAL_ENV)) {
      delete process.env[key];
    }
  }
  Object.assign(process.env, ORIGINAL_ENV);
}

function expectApiError(fn: () => unknown, expected: { code: string; statusCode?: number }) {
  let thrown: any;
  try {
    fn();
  } catch (error) {
    thrown = error;
  }
  expect(thrown).toBeDefined();
  expect(thrown).toMatchObject(expected);
}

beforeEach(() => {
  vi.clearAllMocks();
  process.env.MFA_TOTP_ENCRYPTION_KEY = "test-encryption-key-for-vitest-32chars!!";
  delete process.env.MFA_TOTP_ISSUER;

  prismaMock.$transaction.mockImplementation(async (arg: any) => {
    if (typeof arg === "function") {
      return arg(prismaMock);
    }
    return Promise.all(arg);
  });
});

afterEach(() => {
  restoreEnv();
  vi.restoreAllMocks();
});

describe("mfa.service — crypto helpers", () => {
  it("encrypts and decrypts a TOTP secret round-trip", () => {
    const secret = "JBSWY3DPEHPK3PXP";
    const encrypted = (mfaService as any).encryptSecret(secret);
    const decrypted = (mfaService as any).decryptSecret(encrypted);

    expect(typeof encrypted).toBe("string");
    expect(encrypted.split(".")).toHaveLength(3);
    expect(decrypted).toBe(secret);
  });

  it("rejects malformed encrypted TOTP secrets", () => {
    expectApiError(
      () => (mfaService as any).decryptSecret("malformed-secret"),
      { code: "MFA_TOTP_SECRET_INVALID", statusCode: 500 },
    );
  });

  it("rejects missing MFA_TOTP_ENCRYPTION_KEY", () => {
    delete process.env.MFA_TOTP_ENCRYPTION_KEY;

    expectApiError(
      () => (mfaService as any).deriveKey(),
      { code: "MFA_TOTP_ENCRYPTION_KEY_MISSING", statusCode: 500 },
    );
  });
});

describe("mfa.service — TOTP enrollment", () => {
  it("beginTotpEnrollment returns secret and otpauth URL", async () => {
    prismaMock.user.findUnique.mockResolvedValue({
      id: "user-1",
      email: "user@example.com",
      username: "user1",
    });
    prismaMock.mfaFactor.findFirst.mockResolvedValue(null);
    prismaMock.mfaFactor.updateMany.mockResolvedValue({ count: 0 });
    prismaMock.mfaFactor.create.mockImplementation(async ({ data }: any) => ({
      id: "factor-1",
      label: data.label,
      secretEncrypted: data.secretEncrypted,
    }));

    const result = await mfaService.beginTotpEnrollment("user-1", {});

    expect(result.ok).toBe(true);
    expect(result.factorId).toBe("factor-1");
    expect(result.secret).toBe("JBSWY3DPEHPK3PXP");
    expect(result.otpauthUrl).toContain("otpauth://totp/");
    expect(prismaMock.mfaFactor.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          secretEncrypted: expect.any(String),
        }),
      }),
    );
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({ action: "MFA_TOTP_ENROLLMENT_STARTED" }),
    );
  });

  it("beginTotpEnrollment rejects if TOTP is already active", async () => {
    prismaMock.user.findUnique.mockResolvedValue({
      id: "user-1",
      email: "user@example.com",
    });
    prismaMock.mfaFactor.findFirst.mockResolvedValue({
      id: "existing-factor",
      status: "ACTIVE",
    });

    await expect(mfaService.beginTotpEnrollment("user-1", {})).rejects.toMatchObject({
      code: "MFA_TOTP_ALREADY_ACTIVE",
    });
  });

  it("beginTotpEnrollment revokes stale pending factors before creating a new one", async () => {
    prismaMock.user.findUnique.mockResolvedValue({
      id: "user-1",
      email: "user@example.com",
    });
    prismaMock.mfaFactor.findFirst.mockResolvedValue(null);
    prismaMock.mfaFactor.updateMany.mockResolvedValue({ count: 1 });
    prismaMock.mfaFactor.create.mockResolvedValue({
      id: "factor-2",
      label: "Authenticator app",
    });

    await mfaService.beginTotpEnrollment("user-1", {});

    expect(prismaMock.mfaFactor.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ status: "PENDING" }),
        data: expect.objectContaining({ status: "REVOKED" }),
      }),
    );
  });
});

describe("mfa.service — TOTP activation", () => {
  it("activates enrollment with a valid token using the real encrypted secret path", async () => {
    const encrypted = (mfaService as any).encryptSecret("JBSWY3DPEHPK3PXP");

    prismaMock.mfaFactor.findFirst.mockResolvedValue({
      id: "factor-1",
      userId: "user-1",
      type: "TOTP",
      status: "PENDING",
      secretEncrypted: encrypted,
    });
    authenticatorMock.check.mockReturnValue(true);
    prismaMock.mfaFactor.updateMany.mockResolvedValue({ count: 0 });
    prismaMock.mfaFactor.update.mockResolvedValue({});
    prismaMock.session.updateMany.mockResolvedValue({ count: 2 });

    const result = await mfaService.activateTotpEnrollment("user-1", "session-1", {
      factorId: "factor-1",
      token: "123456",
    });

    expect(result.ok).toBe(true);
    expect(result.method).toBe("TOTP");
    expect(result.revokedOtherSessions).toBe(2);
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({ action: "MFA_TOTP_ENROLLMENT_ACTIVATED" }),
    );
  });

  it("clears MFA on other sessions but preserves the current session during activation", async () => {
    const encrypted = (mfaService as any).encryptSecret("JBSWY3DPEHPK3PXP");

    prismaMock.mfaFactor.findFirst.mockResolvedValue({
      id: "factor-1",
      userId: "user-1",
      type: "TOTP",
      status: "PENDING",
      secretEncrypted: encrypted,
    });
    authenticatorMock.check.mockReturnValue(true);
    prismaMock.mfaFactor.updateMany.mockResolvedValue({ count: 0 });
    prismaMock.mfaFactor.update.mockResolvedValue({});
    prismaMock.session.updateMany
      .mockResolvedValueOnce({ count: 3 })
      .mockResolvedValueOnce({ count: 1 });

    await mfaService.activateTotpEnrollment("user-1", "session-keep", {
      factorId: "factor-1",
      token: "123456",
    });

    expect(prismaMock.session.updateMany).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({
        where: expect.objectContaining({
          userId: "user-1",
          id: { not: "session-keep" },
        }),
      }),
    );
    expect(prismaMock.session.updateMany).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        where: { id: "session-keep" },
        data: expect.objectContaining({
          mfaMethod: null,
          mfaVerifiedAt: null,
        }),
      }),
    );
  });

  it("activateTotpEnrollment rejects invalid TOTP code", async () => {
    const encrypted = (mfaService as any).encryptSecret("JBSWY3DPEHPK3PXP");

    prismaMock.mfaFactor.findFirst.mockResolvedValue({
      id: "factor-1",
      userId: "user-1",
      type: "TOTP",
      status: "PENDING",
      secretEncrypted: encrypted,
    });
    authenticatorMock.check.mockReturnValue(false);

    await expect(
      mfaService.activateTotpEnrollment("user-1", "session-1", {
        factorId: "factor-1",
        token: "000000",
      }),
    ).rejects.toMatchObject({ code: "MFA_TOTP_INVALID_TOKEN" });
  });

  it("activateTotpEnrollment rejects missing factorId or token", async () => {
    await expect(
      mfaService.activateTotpEnrollment("user-1", "session-1", { factorId: "", token: "123456" }),
    ).rejects.toMatchObject({ code: "MFA_TOTP_ACTIVATION_INVALID_INPUT" });

    await expect(
      mfaService.activateTotpEnrollment("user-1", "session-1", { factorId: "factor-1" }),
    ).rejects.toMatchObject({ code: "MFA_TOTP_ACTIVATION_INVALID_INPUT" });
  });
});

describe("mfa.service — TOTP challenge", () => {
  it("stamps the session on a valid TOTP challenge using the real encrypted secret path", async () => {
    const encrypted = (mfaService as any).encryptSecret("JBSWY3DPEHPK3PXP");

    prismaMock.mfaFactor.findFirst.mockResolvedValue({
      id: "factor-1",
      userId: "user-1",
      type: "TOTP",
      status: "ACTIVE",
      secretEncrypted: encrypted,
    });
    authenticatorMock.check.mockReturnValue(true);
    prismaMock.session.update.mockResolvedValue({});

    const result = await mfaService.challengeTotp("user-1", "session-1", { token: "123456" });

    expect(result.ok).toBe(true);
    expect(result.method).toBe("TOTP");
    expect(prismaMock.session.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: "session-1" },
        data: expect.objectContaining({
          mfaMethod: "TOTP",
          mfaVerifiedAt: expect.any(Date),
        }),
      }),
    );
  });

  it("rejects a malformed stored secret during TOTP challenge", async () => {
    prismaMock.mfaFactor.findFirst.mockResolvedValue({
      id: "factor-1",
      userId: "user-1",
      type: "TOTP",
      status: "ACTIVE",
      secretEncrypted: "malformed-secret",
    });

    await expect(
      mfaService.challengeTotp("user-1", "session-1", { token: "123456" }),
    ).rejects.toMatchObject({ code: "MFA_TOTP_SECRET_INVALID" });
  });

  it("challengeTotp rejects invalid code", async () => {
    const encrypted = (mfaService as any).encryptSecret("JBSWY3DPEHPK3PXP");

    prismaMock.mfaFactor.findFirst.mockResolvedValue({
      id: "factor-1",
      userId: "user-1",
      type: "TOTP",
      status: "ACTIVE",
      secretEncrypted: encrypted,
    });
    authenticatorMock.check.mockReturnValue(false);

    await expect(
      mfaService.challengeTotp("user-1", "session-1", { token: "000000" }),
    ).rejects.toMatchObject({ code: "MFA_TOTP_INVALID_TOKEN" });
  });

  it("challengeTotp rejects missing token", async () => {
    await expect(mfaService.challengeTotp("user-1", "session-1", {})).rejects.toMatchObject({
      code: "MFA_TOTP_TOKEN_REQUIRED",
    });
  });

  it("challengeTotp rejects if no session is present", async () => {
    await expect(mfaService.challengeTotp("user-1", undefined, { token: "123456" })).rejects.toMatchObject({
      code: "UNAUTHENTICATED",
    });
  });
});

describe("mfa.service — recovery codes", () => {
  it("regenerateRecoveryCodes generates codes and revokes other sessions", async () => {
    prismaMock.mfaFactor.findFirst.mockResolvedValue({ id: "factor-1" });
    prismaMock.mfaRecoveryCode.deleteMany.mockResolvedValue({ count: 5 });
    prismaMock.mfaRecoveryCode.createMany.mockResolvedValue({ count: 10 });
    prismaMock.session.updateMany
      .mockResolvedValueOnce({ count: 3 })
      .mockResolvedValueOnce({ count: 1 });

    const result = await mfaService.regenerateRecoveryCodes("user-1", "session-1");

    expect(result.ok).toBe(true);
    expect(result.codes).toHaveLength(10);
    expect(result.revokedOtherSessions).toBe(3);

    for (const code of result.codes) {
      expect(code).toMatch(/^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/);
    }

    expect(prismaMock.session.updateMany).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({
        where: expect.objectContaining({
          userId: "user-1",
          id: { not: "session-1" },
        }),
      }),
    );
    expect(prismaMock.session.updateMany).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        where: { id: "session-1" },
      }),
    );
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({ action: "MFA_RECOVERY_CODES_REGENERATED" }),
    );
  });

  it("regenerateRecoveryCodes clamps requested counts to the supported range", async () => {
    prismaMock.mfaFactor.findFirst.mockResolvedValue({ id: "factor-1" });
    prismaMock.mfaRecoveryCode.deleteMany.mockResolvedValue({ count: 0 });
    prismaMock.mfaRecoveryCode.createMany.mockResolvedValue({ count: 8 });
    prismaMock.session.updateMany.mockResolvedValue({ count: 0 });

    const resultLow = await mfaService.regenerateRecoveryCodes("user-1", "session-1", { count: 3 });
    expect(resultLow.count).toBe(8);

    const resultHigh = await mfaService.regenerateRecoveryCodes("user-1", "session-1", { count: 50 });
    expect(resultHigh.count).toBe(12);
  });

  it("normalizes recovery-code input before lookup and stamps the session", async () => {
    prismaMock.mfaRecoveryCode.findFirst.mockResolvedValue({
      id: "rc-1",
      userId: "user-1",
      consumedAt: null,
    });
    prismaMock.mfaRecoveryCode.update.mockResolvedValue({});
    prismaMock.session.update.mockResolvedValue({});

    const result = await mfaService.challengeRecoveryCode("user-1", "session-1", {
      code: " abcd-efgh-ijkl ",
    });

    expect(result.ok).toBe(true);
    expect(result.method).toBe("RECOVERY_CODE");
    expect(prismaMock.mfaRecoveryCode.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          codeHash: (mfaService as any).hashRecoveryCode("ABCD-EFGH-IJKL"),
        }),
      }),
    );
    expect(prismaMock.session.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: "session-1" },
        data: expect.objectContaining({
          mfaMethod: "RECOVERY_CODE",
          mfaVerifiedAt: expect.any(Date),
        }),
      }),
    );
  });

  it("challengeRecoveryCode rejects when the recovery code was already consumed or invalid", async () => {
    prismaMock.mfaRecoveryCode.findFirst.mockResolvedValue(null);

    await expect(
      mfaService.challengeRecoveryCode("user-1", "session-1", { code: "INVALID-CODE-HERE" }),
    ).rejects.toMatchObject({ code: "MFA_RECOVERY_CODE_INVALID" });
  });

  it("challengeRecoveryCode rejects missing code", async () => {
    await expect(mfaService.challengeRecoveryCode("user-1", "session-1", {})).rejects.toMatchObject({
      code: "MFA_RECOVERY_CODE_REQUIRED",
    });
  });

  it("challengeRecoveryCode rejects without a session", async () => {
    await expect(
      mfaService.challengeRecoveryCode("user-1", undefined, { code: "ABCD-EFGH-IJKL" }),
    ).rejects.toMatchObject({ code: "UNAUTHENTICATED" });
  });
});
''').lstrip())

print("Patched package.json, hardened generateRecoveryCode(), and wrote apps/api/test/mfa.service.test.ts for Phase 17 A4.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 17 A4 patch applied."
