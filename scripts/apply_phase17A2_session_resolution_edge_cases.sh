#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "" ]]; then
  ROOT="$1"
else
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
fi

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import re
import sys
from textwrap import dedent

root = Path(sys.argv[1]).resolve()

def fail(msg: str):
    raise SystemExit(msg)

pkg_path = root / "apps/api/package.json"
auth_path = root / "apps/api/src/modules/auth/auth.service.ts"
test_path = root / "apps/api/test/session.resolution.test.ts"

if not pkg_path.exists():
    fail(f"Missing file: {pkg_path}")
if not auth_path.exists():
    fail(f"Missing file: {auth_path}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:auth:session-resolution"] = "vitest run test/session.resolution.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

auth = auth_path.read_text()

old_block = dedent('''
    const session = await prisma.session.findUnique({
      where: { id: parsed.sessionId },
      include: { user: true },
    });
    if (!session) return null;
    if (session.revokedAt) return null;
    if (session.expiresAt.getTime() <= Date.now()) return null;
    if (session.user.status === "SUSPENDED" || session.user.status === "CLOSED") return null;
    const secretOk = await verifySessionSecret(session.refreshTokenHash, parsed.secret);
    if (!secretOk) return null;
''').strip()

new_block = dedent('''
    const session = await prisma.session.findUnique({
      where: { id: parsed.sessionId },
      include: { user: true },
    });
    if (!session) return null;
    if (!session.user) return null;
    if (session.revokedAt) return null;
    if (session.expiresAt.getTime() <= Date.now()) return null;
    if (session.user.status === "SUSPENDED" || session.user.status === "CLOSED") return null;
    let secretOk = false;
    try {
      secretOk = await verifySessionSecret(session.refreshTokenHash, parsed.secret);
    } catch {
      return null;
    }
    if (!secretOk) return null;
''').strip()

if old_block in auth:
    auth = auth.replace(old_block, new_block, 1)
    auth_path.write_text(auth)
    auth_status = "patched"
elif "if (!session.user) return null;" in auth and "let secretOk = false;" in auth and "catch {" in auth:
    auth_status = "already_hardened"
else:
    fail("Could not patch resolveAuthFromRequest guard block in auth.service.ts")

test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(dedent('''
import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  prismaMock,
  recordSecurityAudit,
  sessionAuthMock,
} = vi.hoisted(() => ({
  prismaMock: {
    session: { findUnique: vi.fn(), updateMany: vi.fn() },
    user: { findFirst: vi.fn(), findUnique: vi.fn() },
    verificationCode: { updateMany: vi.fn(), create: vi.fn() },
    $transaction: vi.fn(),
  },
  recordSecurityAudit: vi.fn(),
  sessionAuthMock: {
    buildSessionCookieValue: vi.fn(() => "session-cookie"),
    clearSessionCookie: vi.fn(),
    createSessionSecret: vi.fn(() => "secret"),
    getCookieFromRequest: vi.fn(),
    getSessionExpiryDate: vi.fn(() => new Date("2030-01-01T00:00:00.000Z")),
    hashSessionSecret: vi.fn(async () => "secret-hash"),
    parseSessionCookieValue: vi.fn(),
    SESSION_COOKIE_NAME: "dcapx_session",
    setSessionCookie: vi.fn(),
    verifySessionSecret: vi.fn(),
  },
}));

vi.mock("argon2", () => ({
  default: {
    verify: vi.fn(),
    hash: vi.fn(async () => "hashed"),
  },
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/service/security-audit", () => ({ recordSecurityAudit }));
vi.mock("../src/lib/service/audit", () => ({ writeAuditEvent: vi.fn() }));
vi.mock("../src/lib/service/tx", () => ({ withTx: vi.fn() }));
vi.mock("../src/lib/service/zod", () => ({ parseDto: vi.fn() }));
vi.mock("../src/modules/verification/verification.service", () => ({
  verificationService: { requestPasswordReset: vi.fn(), resetPassword: vi.fn() },
}));
vi.mock("../src/modules/auth/auth.dto", () => ({ registerDto: {} }));
vi.mock("../src/modules/auth/auth.mappers", () => ({ mapRegisterDtoToUserCreate: vi.fn() }));
vi.mock("../src/lib/session-auth", () => sessionAuthMock);

import { authService } from "../src/modules/auth/auth.service";

describe("authService.resolveAuthFromRequest", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  const makeReq = (cookie?: string) =>
    ({ headers: { cookie: cookie ? `dcapx_session=${cookie}` : "" } }) as any;

  it("returns null when no session cookie is present", async () => {
    sessionAuthMock.getCookieFromRequest.mockReturnValue(null);
    sessionAuthMock.parseSessionCookieValue.mockReturnValue(null);

    const result = await authService.resolveAuthFromRequest(makeReq());
    expect(result).toBeNull();
  });

  it("returns null when the session cookie cannot be parsed", async () => {
    sessionAuthMock.getCookieFromRequest.mockReturnValue("bad-cookie");
    sessionAuthMock.parseSessionCookieValue.mockReturnValue(null);

    const result = await authService.resolveAuthFromRequest(makeReq("bad-cookie"));
    expect(result).toBeNull();
  });

  it("returns null when session is not found in the database", async () => {
    sessionAuthMock.getCookieFromRequest.mockReturnValue("session-1.secret");
    sessionAuthMock.parseSessionCookieValue.mockReturnValue({
      sessionId: "session-1",
      secret: "secret",
    });
    prismaMock.session.findUnique.mockResolvedValue(null);

    const result = await authService.resolveAuthFromRequest(makeReq("session-1.secret"));
    expect(result).toBeNull();
  });

  it("returns null when session user relation is missing", async () => {
    sessionAuthMock.getCookieFromRequest.mockReturnValue("session-1.secret");
    sessionAuthMock.parseSessionCookieValue.mockReturnValue({
      sessionId: "session-1",
      secret: "secret",
    });
    prismaMock.session.findUnique.mockResolvedValue({
      id: "session-1",
      userId: "user-1",
      revokedAt: null,
      expiresAt: new Date("2030-01-01T00:00:00.000Z"),
      refreshTokenHash: "hash",
      user: null,
    });

    const result = await authService.resolveAuthFromRequest(makeReq("session-1.secret"));
    expect(result).toBeNull();
  });

  it("returns null when session is revoked", async () => {
    sessionAuthMock.getCookieFromRequest.mockReturnValue("session-1.secret");
    sessionAuthMock.parseSessionCookieValue.mockReturnValue({
      sessionId: "session-1",
      secret: "secret",
    });
    prismaMock.session.findUnique.mockResolvedValue({
      id: "session-1",
      userId: "user-1",
      revokedAt: new Date("2024-01-01T00:00:00.000Z"),
      expiresAt: new Date("2030-01-01T00:00:00.000Z"),
      refreshTokenHash: "hash",
      user: { status: "ACTIVE" },
    });

    const result = await authService.resolveAuthFromRequest(makeReq("session-1.secret"));
    expect(result).toBeNull();
  });

  it("returns null when session is expired", async () => {
    sessionAuthMock.getCookieFromRequest.mockReturnValue("session-1.secret");
    sessionAuthMock.parseSessionCookieValue.mockReturnValue({
      sessionId: "session-1",
      secret: "secret",
    });
    prismaMock.session.findUnique.mockResolvedValue({
      id: "session-1",
      userId: "user-1",
      revokedAt: null,
      expiresAt: new Date("2020-01-01T00:00:00.000Z"),
      refreshTokenHash: "hash",
      user: { status: "ACTIVE" },
    });

    const result = await authService.resolveAuthFromRequest(makeReq("session-1.secret"));
    expect(result).toBeNull();
  });

  it("returns null when user is suspended", async () => {
    sessionAuthMock.getCookieFromRequest.mockReturnValue("session-1.secret");
    sessionAuthMock.parseSessionCookieValue.mockReturnValue({
      sessionId: "session-1",
      secret: "secret",
    });
    prismaMock.session.findUnique.mockResolvedValue({
      id: "session-1",
      userId: "user-1",
      revokedAt: null,
      expiresAt: new Date("2030-01-01T00:00:00.000Z"),
      refreshTokenHash: "hash",
      user: { status: "SUSPENDED" },
    });

    const result = await authService.resolveAuthFromRequest(makeReq("session-1.secret"));
    expect(result).toBeNull();
  });

  it("returns null when user is closed", async () => {
    sessionAuthMock.getCookieFromRequest.mockReturnValue("session-1.secret");
    sessionAuthMock.parseSessionCookieValue.mockReturnValue({
      sessionId: "session-1",
      secret: "secret",
    });
    prismaMock.session.findUnique.mockResolvedValue({
      id: "session-1",
      userId: "user-1",
      revokedAt: null,
      expiresAt: new Date("2030-01-01T00:00:00.000Z"),
      refreshTokenHash: "hash",
      user: { status: "CLOSED" },
    });

    const result = await authService.resolveAuthFromRequest(makeReq("session-1.secret"));
    expect(result).toBeNull();
  });

  it("returns null when session secret does not match the stored hash", async () => {
    sessionAuthMock.getCookieFromRequest.mockReturnValue("session-1.wrong-secret");
    sessionAuthMock.parseSessionCookieValue.mockReturnValue({
      sessionId: "session-1",
      secret: "wrong-secret",
    });
    prismaMock.session.findUnique.mockResolvedValue({
      id: "session-1",
      userId: "user-1",
      revokedAt: null,
      expiresAt: new Date("2030-01-01T00:00:00.000Z"),
      refreshTokenHash: "hash",
      user: { status: "ACTIVE" },
    });
    sessionAuthMock.verifySessionSecret.mockResolvedValue(false);

    const result = await authService.resolveAuthFromRequest(makeReq("session-1.wrong-secret"));
    expect(result).toBeNull();
  });

  it("returns null when session secret verification throws", async () => {
    sessionAuthMock.getCookieFromRequest.mockReturnValue("session-1.secret");
    sessionAuthMock.parseSessionCookieValue.mockReturnValue({
      sessionId: "session-1",
      secret: "secret",
    });
    prismaMock.session.findUnique.mockResolvedValue({
      id: "session-1",
      userId: "user-1",
      revokedAt: null,
      expiresAt: new Date("2030-01-01T00:00:00.000Z"),
      refreshTokenHash: "hash",
      user: { status: "ACTIVE" },
    });
    sessionAuthMock.verifySessionSecret.mockRejectedValue(new Error("argon2 boom"));

    const result = await authService.resolveAuthFromRequest(makeReq("session-1.secret"));
    expect(result).toBeNull();
  });

  it("returns auth context with MFA fields for a valid session", async () => {
    const mfaVerifiedAt = new Date("2025-06-01T12:00:00.000Z");
    sessionAuthMock.getCookieFromRequest.mockReturnValue("session-1.secret");
    sessionAuthMock.parseSessionCookieValue.mockReturnValue({
      sessionId: "session-1",
      secret: "secret",
    });
    prismaMock.session.findUnique.mockResolvedValue({
      id: "session-1",
      userId: "user-1",
      revokedAt: null,
      expiresAt: new Date("2030-01-01T00:00:00.000Z"),
      refreshTokenHash: "hash",
      mfaMethod: "TOTP",
      mfaVerifiedAt,
      user: { status: "ACTIVE" },
    });
    sessionAuthMock.verifySessionSecret.mockResolvedValue(true);

    const result = await authService.resolveAuthFromRequest(makeReq("session-1.secret"));

    expect(result).toEqual({
      userId: "user-1",
      sessionId: "session-1",
      mfaMethod: "TOTP",
      mfaVerifiedAt,
    });
  });
});

describe("authService.logout", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("revokes the parsed session id and clears the cookie", async () => {
    sessionAuthMock.getCookieFromRequest.mockReturnValue("session-1.secret");
    sessionAuthMock.parseSessionCookieValue.mockReturnValue({
      sessionId: "session-1",
      secret: "secret",
    });
    prismaMock.session.findUnique.mockResolvedValue({
      id: "session-1",
      userId: "user-1",
      revokedAt: null,
      expiresAt: new Date("2030-01-01T00:00:00.000Z"),
      refreshTokenHash: "hash",
      user: { status: "ACTIVE" },
    });
    sessionAuthMock.verifySessionSecret.mockResolvedValue(true);
    prismaMock.session.updateMany.mockResolvedValue({ count: 1 });

    const req: any = { headers: {}, socket: { remoteAddress: "127.0.0.1" } };
    const res: any = {};

    const result = await authService.logout(req, res);

    expect(result).toEqual({ ok: true });
    expect(prismaMock.session.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ id: "session-1", revokedAt: null }),
        data: expect.objectContaining({ revokedAt: expect.any(Date) }),
      }),
    );
    expect(sessionAuthMock.clearSessionCookie).toHaveBeenCalledWith(res);
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "AUTH_LOGOUT",
        resourceType: "AUTH_SESSION",
        resourceId: "session-1",
      }),
    );
  });

  it("clears the cookie and returns ok when no session cookie is present", async () => {
    sessionAuthMock.getCookieFromRequest.mockReturnValue(null);
    sessionAuthMock.parseSessionCookieValue.mockReturnValue(null);

    const req: any = { headers: {}, socket: { remoteAddress: "127.0.0.1" } };
    const res: any = {};

    const result = await authService.logout(req, res);

    expect(result).toEqual({ ok: true });
    expect(prismaMock.session.updateMany).not.toHaveBeenCalled();
    expect(sessionAuthMock.clearSessionCookie).toHaveBeenCalledWith(res);
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "AUTH_LOGOUT",
        resourceType: "AUTH_SESSION",
        resourceId: null,
      }),
    );
  });

  it("clears the cookie and remains idempotent when no active session matches", async () => {
    sessionAuthMock.getCookieFromRequest.mockReturnValue("session-404.secret");
    sessionAuthMock.parseSessionCookieValue.mockReturnValue({
      sessionId: "session-404",
      secret: "secret",
    });
    prismaMock.session.findUnique.mockResolvedValue(null);
    prismaMock.session.updateMany.mockResolvedValue({ count: 0 });

    const req: any = { headers: {}, socket: { remoteAddress: "127.0.0.1" } };
    const res: any = {};

    const result = await authService.logout(req, res);

    expect(result).toEqual({ ok: true });
    expect(prismaMock.session.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ id: "session-404", revokedAt: null }),
      }),
    );
    expect(sessionAuthMock.clearSessionCookie).toHaveBeenCalledWith(res);
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "AUTH_LOGOUT",
        resourceType: "AUTH_SESSION",
        resourceId: "session-404",
      }),
    );
  });
});
''').lstrip())

print(f"Patched package.json, {'hardened' if auth_status == 'patched' else 'confirmed'} resolveAuthFromRequest guards, and wrote apps/api/test/session.resolution.test.ts for Phase 17 A2.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 17 A2 patch applied."
