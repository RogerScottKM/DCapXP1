import type { Request, Response } from "express";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { prismaMock, recordSecurityAudit, resolveAuthFromRequest } = vi.hoisted(() => ({
  prismaMock: {
    roleAssignment: { findMany: vi.fn() },
    kycCase: { findFirst: vi.fn() },
    kyc: { findFirst: vi.fn() },
  },
  recordSecurityAudit: vi.fn(),
  resolveAuthFromRequest: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/service/security-audit", () => ({ recordSecurityAudit }));
vi.mock("../src/modules/auth/auth.service", () => ({
  authService: { resolveAuthFromRequest },
}));

import {
  requireAdminRecentMfa,
  requireAuth,
  requireLiveModeEligible,
  requireRecentMfa,
  requireRole,
} from "../src/middleware/require-auth";

function createReq(overrides: Partial<Request> = {}): Request {
  return {
    method: "POST",
    originalUrl: "/api/test",
    path: "/api/test",
    body: {},
    query: {},
    headers: {},
    ...overrides,
  } as Request;
}

function createRes(): Response {
  return {} as Response;
}

function runMiddleware(
  mw: (req: Request, res: Response, next: (error?: unknown) => void) => Promise<void> | void,
  req: Request,
) {
  return new Promise<unknown>((resolve) => {
    mw(req, createRes(), (error?: unknown) => resolve(error));
  });
}

function mockAuthWithRoles(
  roles: string[],
  mfaVerifiedAt: Date | null = null,
  mfaMethod: string | null = null,
) {
  resolveAuthFromRequest.mockResolvedValue({
    userId: "user-1",
    sessionId: "session-1",
    mfaMethod,
    mfaVerifiedAt,
  });
  prismaMock.roleAssignment.findMany.mockResolvedValue(
    roles.map((roleCode) => ({ roleCode })),
  );
}

describe("requireAuth", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    prismaMock.roleAssignment.findMany.mockResolvedValue([]);
    prismaMock.kycCase.findFirst.mockResolvedValue(null);
    prismaMock.kyc.findFirst.mockResolvedValue(null);
  });

  it("passes when session is valid and attaches auth context", async () => {
    mockAuthWithRoles(["USER"]);

    const req = createReq();
    const error = await runMiddleware(requireAuth, req);

    expect(error).toBeUndefined();
    expect(req.auth).toBeDefined();
    expect(req.auth).toEqual(
      expect.objectContaining({
        userId: "user-1",
        sessionId: "session-1",
        roleCodes: ["USER"],
        mfaSatisfied: false,
      }),
    );
  });

  it("rejects with UNAUTHENTICATED when no session", async () => {
    resolveAuthFromRequest.mockResolvedValue(null);

    const req = createReq();
    const error = await runMiddleware(requireAuth, req);

    expect(error).toMatchObject({ code: "UNAUTHENTICATED" });
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({ action: "AUTHZ_UNAUTHENTICATED_DENIED" }),
    );
  });
});

describe("requireRole", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    prismaMock.kycCase.findFirst.mockResolvedValue(null);
    prismaMock.kyc.findFirst.mockResolvedValue(null);
  });

  it("passes when user has required role", async () => {
    mockAuthWithRoles(["ADMIN"]);

    const req = createReq();
    const error = await runMiddleware(requireRole("ADMIN"), req);

    expect(error).toBeUndefined();
  });

  it("passes when user has any of multiple allowed roles", async () => {
    mockAuthWithRoles(["AUDITOR"]);

    const req = createReq();
    const error = await runMiddleware(requireRole("ADMIN", "AUDITOR"), req);

    expect(error).toBeUndefined();
  });

  it("rejects when user lacks required role", async () => {
    mockAuthWithRoles(["USER"]);

    const req = createReq();
    const error = await runMiddleware(requireRole("ADMIN"), req);

    expect(error).toMatchObject({ code: "FORBIDDEN" });
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({ action: "AUTHZ_ROLE_DENIED" }),
    );
  });
});

describe("requireRecentMfa", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    prismaMock.kycCase.findFirst.mockResolvedValue(null);
    prismaMock.kyc.findFirst.mockResolvedValue(null);
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-14T00:00:00.000Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("passes when MFA was verified recently", async () => {
    mockAuthWithRoles(["USER"], new Date("2026-04-13T23:50:01.000Z"), "TOTP");

    const req = createReq();
    const error = await runMiddleware(requireRecentMfa(), req);

    expect(error).toBeUndefined();
    expect(req.auth).toEqual(expect.objectContaining({ mfaSatisfied: true }));
  });

  it("passes exactly at the maxAge boundary", async () => {
    mockAuthWithRoles(["USER"], new Date("2026-04-13T23:45:00.000Z"), "TOTP");

    const req = createReq();
    const error = await runMiddleware(requireRecentMfa(), req);

    expect(error).toBeUndefined();
  });

  it("rejects just beyond the maxAge boundary", async () => {
    mockAuthWithRoles(["USER"], new Date("2026-04-13T23:44:59.000Z"), "TOTP");

    const req = createReq();
    const error = await runMiddleware(requireRecentMfa(), req);

    expect(error).toMatchObject({ code: "MFA_REQUIRED" });
    expect(req.auth).toEqual(expect.objectContaining({ mfaSatisfied: false }));
  });

  it("rejects when MFA was never verified", async () => {
    mockAuthWithRoles(["USER"], null, null);

    const req = createReq();
    const error = await runMiddleware(requireRecentMfa(), req);

    expect(error).toMatchObject({ code: "MFA_REQUIRED" });
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({ action: "AUTHZ_MFA_REQUIRED_DENIED" }),
    );
  });
});

describe("requireAdminRecentMfa", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    prismaMock.kycCase.findFirst.mockResolvedValue(null);
    prismaMock.kyc.findFirst.mockResolvedValue(null);
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-14T00:00:00.000Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("passes for ADMIN with recent MFA", async () => {
    mockAuthWithRoles(["ADMIN"], new Date("2026-04-13T23:55:00.000Z"), "TOTP");

    const req = createReq();
    const error = await runMiddleware(requireAdminRecentMfa(), req);

    expect(error).toBeUndefined();
  });

  it("passes for AUDITOR with recent MFA", async () => {
    mockAuthWithRoles(["AUDITOR"], new Date("2026-04-13T23:55:00.000Z"), "TOTP");

    const req = createReq();
    const error = await runMiddleware(requireAdminRecentMfa(), req);

    expect(error).toBeUndefined();
  });

  it("rejects USER role even with recent MFA", async () => {
    mockAuthWithRoles(["USER"], new Date("2026-04-13T23:55:00.000Z"), "TOTP");

    const req = createReq();
    const error = await runMiddleware(requireAdminRecentMfa(), req);

    expect(error).toMatchObject({ code: "FORBIDDEN" });
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({ action: "AUTHZ_ADMIN_ROLE_DENIED" }),
    );
  });

  it("rejects ADMIN without recent MFA", async () => {
    mockAuthWithRoles(["ADMIN"], null, null);

    const req = createReq();
    const error = await runMiddleware(requireAdminRecentMfa(), req);

    expect(error).toMatchObject({ code: "MFA_REQUIRED" });
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({ action: "AUTHZ_ADMIN_MFA_REQUIRED_DENIED" }),
    );
  });
});

describe("requireLiveModeEligible", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    prismaMock.kycCase.findFirst.mockResolvedValue(null);
    prismaMock.kyc.findFirst.mockResolvedValue(null);
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-14T00:00:00.000Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("passes for non-LIVE mode requests without auth checks", async () => {
    const req = createReq({ body: { mode: "PAPER" } });
    const error = await runMiddleware(requireLiveModeEligible(), req);

    expect(error).toBeUndefined();
    expect(resolveAuthFromRequest).not.toHaveBeenCalled();
  });

  it("passes for LIVE mode with recent MFA and approved KYC", async () => {
    mockAuthWithRoles(["USER"], new Date("2026-04-13T23:55:00.000Z"), "TOTP");
    prismaMock.kycCase.findFirst.mockResolvedValue({ id: "kyc-1" });

    const req = createReq({ body: { mode: "LIVE" } });
    const error = await runMiddleware(requireLiveModeEligible(), req);

    expect(error).toBeUndefined();
  });

  it("rejects LIVE mode without recent MFA", async () => {
    mockAuthWithRoles(["USER"], null, null);

    const req = createReq({ body: { mode: "LIVE" } });
    const error = await runMiddleware(requireLiveModeEligible(), req);

    expect(error).toMatchObject({ code: "MFA_REQUIRED" });
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({ action: "AUTHZ_LIVE_MFA_REQUIRED_DENIED" }),
    );
  });

  it("rejects LIVE mode when KYC is pending", async () => {
    mockAuthWithRoles(["USER"], new Date("2026-04-13T23:55:00.000Z"), "TOTP");
    prismaMock.kycCase.findFirst.mockResolvedValue(null);
    prismaMock.kyc.findFirst.mockResolvedValue(null);

    const req = createReq({ body: { mode: "LIVE" } });
    const error = await runMiddleware(requireLiveModeEligible(), req);

    expect(error).toMatchObject({ code: "LIVE_MODE_NOT_ALLOWED" });
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({ action: "LIVE_MODE_DENIED" }),
    );
  });

  it("rejects LIVE mode when KYC is under review", async () => {
    mockAuthWithRoles(["USER"], new Date("2026-04-13T23:55:00.000Z"), "TOTP");
    prismaMock.kycCase.findFirst.mockResolvedValue(null);
    prismaMock.kyc.findFirst.mockResolvedValue(null);

    const req = createReq({ body: { mode: "live" }, query: { status: "UNDER_REVIEW" } as any });
    const error = await runMiddleware(requireLiveModeEligible(), req);

    expect(error).toMatchObject({ code: "LIVE_MODE_NOT_ALLOWED" });
  });

  it("rejects LIVE mode when KYC is rejected", async () => {
    mockAuthWithRoles(["USER"], new Date("2026-04-13T23:55:00.000Z"), "TOTP");
    prismaMock.kycCase.findFirst.mockResolvedValue(null);
    prismaMock.kyc.findFirst.mockResolvedValue(null);

    const req = createReq({ body: { mode: "LIVE" } });
    const error = await runMiddleware(requireLiveModeEligible(), req);

    expect(error).toMatchObject({ code: "LIVE_MODE_NOT_ALLOWED" });
  });

  it("uses body mode ahead of query and header mode", async () => {
    const req = createReq({
      body: { mode: "PAPER" },
      query: { mode: "LIVE" } as any,
      headers: { "x-mode": "LIVE" } as any,
    });

    const error = await runMiddleware(requireLiveModeEligible(), req);

    expect(error).toBeUndefined();
    expect(resolveAuthFromRequest).not.toHaveBeenCalled();
  });

  it("reads LIVE mode from query string", async () => {
    mockAuthWithRoles(["USER"], null, null);

    const req = createReq({ query: { mode: "LIVE" } as any });
    const error = await runMiddleware(requireLiveModeEligible(), req);

    expect(error).toMatchObject({ code: "MFA_REQUIRED" });
  });

  it("reads LIVE mode from x-mode header", async () => {
    mockAuthWithRoles(["USER"], null, null);

    const req = createReq({ headers: { "x-mode": "LIVE" } as any });
    const error = await runMiddleware(requireLiveModeEligible(), req);

    expect(error).toMatchObject({ code: "MFA_REQUIRED" });
  });

  it("is case-insensitive for requested mode", async () => {
    mockAuthWithRoles(["USER"], null, null);

    const req = createReq({ body: { mode: "live" } });
    const error = await runMiddleware(requireLiveModeEligible(), req);

    expect(error).toMatchObject({ code: "MFA_REQUIRED" });
  });
});
