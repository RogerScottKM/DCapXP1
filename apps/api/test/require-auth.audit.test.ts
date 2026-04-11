import type { Request, Response } from "express";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { prismaMock, recordSecurityAudit, resolveAuthFromRequest } = vi.hoisted(() => ({
  prismaMock: {
    roleAssignment: { findMany: vi.fn() },
    kycCase: { findFirst: vi.fn() },
  },
  recordSecurityAudit: vi.fn(),
  resolveAuthFromRequest: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/service/security-audit", () => ({ recordSecurityAudit }));
vi.mock("../src/modules/auth/auth.service", () => ({
  authService: {
    resolveAuthFromRequest,
  },
}));

import { requireLiveModeEligible, requireRecentMfa, requireRole } from "../src/middleware/require-auth";

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

describe("require-auth audit coverage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    prismaMock.roleAssignment.findMany.mockResolvedValue([]);
    prismaMock.kycCase.findFirst.mockResolvedValue(null);
  });

  it("records AUTHZ_MFA_REQUIRED_DENIED when recent MFA is missing", async () => {
    resolveAuthFromRequest.mockResolvedValue({
      userId: "user-1",
      sessionId: "session-1",
      mfaMethod: null,
      mfaVerifiedAt: null,
    });

    const req = createReq();
    const error = await runMiddleware(requireRecentMfa(), req);

    expect(error).toMatchObject({ code: "MFA_REQUIRED" });
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({ action: "AUTHZ_MFA_REQUIRED_DENIED" }),
    );
  });

  it("records AUTHZ_ROLE_DENIED when role is missing", async () => {
    resolveAuthFromRequest.mockResolvedValue({
      userId: "user-1",
      sessionId: "session-1",
      mfaMethod: null,
      mfaVerifiedAt: new Date().toISOString(),
    });
    prismaMock.roleAssignment.findMany.mockResolvedValue([{ roleCode: "USER" }]);

    const req = createReq();
    const error = await runMiddleware(requireRole("ADMIN"), req);

    expect(error).toMatchObject({ code: "FORBIDDEN" });
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({ action: "AUTHZ_ROLE_DENIED" }),
    );
  });

  it("records LIVE_MODE_DENIED when approved KYC is missing for LIVE mode", async () => {
    resolveAuthFromRequest.mockResolvedValue({
      userId: "user-1",
      sessionId: "session-1",
      mfaMethod: "TOTP",
      mfaVerifiedAt: new Date().toISOString(),
    });
    prismaMock.roleAssignment.findMany.mockResolvedValue([{ roleCode: "ADMIN" }]);
    prismaMock.kycCase.findFirst.mockResolvedValue(null);

    const req = createReq({ body: { mode: "LIVE" } });
    const error = await runMiddleware(requireLiveModeEligible(), req);

    expect(error).toMatchObject({ code: "LIVE_MODE_NOT_ALLOWED" });
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({ action: "LIVE_MODE_DENIED" }),
    );
  });
});
