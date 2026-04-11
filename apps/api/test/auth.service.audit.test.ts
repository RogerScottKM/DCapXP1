import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  prismaMock,
  recordSecurityAudit,
  setSessionCookie,
  clearSessionCookie,
  verificationService,
} = vi.hoisted(() => ({
  prismaMock: {
    user: { findFirst: vi.fn(), findUnique: vi.fn() },
    session: { create: vi.fn(), updateMany: vi.fn(), findUnique: vi.fn() },
    verificationCode: { updateMany: vi.fn(), create: vi.fn(), findFirst: vi.fn(), update: vi.fn() },
    $transaction: vi.fn(),
  },
  recordSecurityAudit: vi.fn(),
  setSessionCookie: vi.fn(),
  clearSessionCookie: vi.fn(),
  verificationService: {
    requestPasswordReset: vi.fn(),
    resetPassword: vi.fn(),
  },
}));

vi.mock("argon2", () => ({
  default: {
    verify: vi.fn(),
    hash: vi.fn(),
  },
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/service/security-audit", () => ({ recordSecurityAudit }));
vi.mock("../src/lib/service/audit", () => ({ writeAuditEvent: vi.fn() }));
vi.mock("../src/lib/service/tx", () => ({ withTx: vi.fn() }));
vi.mock("../src/lib/service/zod", () => ({ parseDto: vi.fn() }));
vi.mock("../src/modules/verification/verification.service", () => ({ verificationService }));
vi.mock("../src/modules/auth/auth.dto", () => ({ registerDto: {} }));
vi.mock("../src/modules/auth/auth.mappers", () => ({ mapRegisterDtoToUserCreate: vi.fn() }));
vi.mock("../src/lib/session-auth", () => ({
  buildSessionCookieValue: vi.fn(() => "session-cookie"),
  clearSessionCookie,
  createSessionSecret: vi.fn(() => "secret"),
  getCookieFromRequest: vi.fn(() => "raw-cookie"),
  getSessionExpiryDate: vi.fn(() => new Date("2030-01-01T00:00:00.000Z")),
  hashSessionSecret: vi.fn(async () => "secret-hash"),
  parseSessionCookieValue: vi.fn(() => ({ sessionId: "session-1", secret: "secret" })),
  SESSION_COOKIE_NAME: "dcapx_session",
  setSessionCookie,
  verifySessionSecret: vi.fn(async () => true),
}));

import argon2 from "argon2";
import { authService } from "../src/modules/auth/auth.service";

describe("auth.service audit coverage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    prismaMock.$transaction.mockImplementation(async (ops: any[]) => Promise.all(ops));
  });

  it("records AUTH_LOGIN_SUCCEEDED on successful login", async () => {
    prismaMock.user.findFirst.mockResolvedValue({
      id: "user-1",
      email: "user@example.com",
      username: "user1",
      status: "ACTIVE",
      passwordHash: "hash",
      profile: null,
      roles: [],
    });
    (argon2.verify as any).mockResolvedValue(true);
    prismaMock.session.create.mockResolvedValue({
      id: "session-1",
      expiresAt: new Date("2030-01-01T00:00:00.000Z"),
    });

    const req: any = { headers: { "user-agent": "Vitest" }, socket: { remoteAddress: "127.0.0.1" } };
    const res: any = {};

    const result = await authService.login(req, res, {
      identifier: "user@example.com",
      password: "password",
    });

    expect(result.ok).toBe(true);
    expect(setSessionCookie).toHaveBeenCalled();
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "AUTH_LOGIN_SUCCEEDED",
        actorId: "user-1",
        resourceId: "session-1",
      }),
    );
  });

  it("records AUTH_LOGIN_FAILED when credentials are invalid", async () => {
    prismaMock.user.findFirst.mockResolvedValue(null);

    const req: any = { headers: {}, socket: { remoteAddress: "127.0.0.1" } };
    const res: any = {};

    await expect(
      authService.login(req, res, { identifier: "missing@example.com", password: "bad" }),
    ).rejects.toMatchObject({
      code: "LOGIN_INVALID_CREDENTIALS",
    });

    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "AUTH_LOGIN_FAILED",
      }),
    );
  });

  it("records AUTH_LOGOUT on logout", async () => {
    prismaMock.session.findUnique.mockResolvedValue({
      id: "session-1",
      userId: "user-1",
      mfaMethod: null,
      mfaVerifiedAt: null,
      revokedAt: null,
      expiresAt: new Date("2030-01-01T00:00:00.000Z"),
      refreshTokenHash: "hash",
      user: { status: "ACTIVE" },
    });
    prismaMock.session.updateMany.mockResolvedValue({ count: 1 });

    const req: any = { headers: {}, socket: { remoteAddress: "127.0.0.1" } };
    const res: any = {};

    const result = await authService.logout(req, res);
    expect(result.ok).toBe(true);
    expect(clearSessionCookie).toHaveBeenCalled();
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "AUTH_LOGOUT",
      }),
    );
  });
});
