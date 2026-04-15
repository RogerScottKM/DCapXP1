import express from "express";
import request from "supertest";
import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  prismaMock,
  recordSecurityAudit,
  resolveAuthFromRequest,
  runReconciliation,
} = vi.hoisted(() => ({
  prismaMock: {
    roleAssignment: { findMany: vi.fn() },
  },
  recordSecurityAudit: vi.fn(),
  resolveAuthFromRequest: vi.fn(),
  runReconciliation: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/service/security-audit", () => ({ recordSecurityAudit }));
vi.mock("../src/modules/auth/auth.service", () => ({
  authService: { resolveAuthFromRequest },
}));
vi.mock("../src/workers/reconciliation", () => ({
  runReconciliation,
}));
vi.mock("../src/middleware/audit-privileged", () => ({
  auditPrivilegedRequest: () => (_req: any, _res: any, next: (err?: unknown) => void) => next(),
}));

import reconciliationRoutes from "../src/routes/reconciliation";

describe("reconciliation routes", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    resolveAuthFromRequest.mockResolvedValue(null);
    prismaMock.roleAssignment.findMany.mockResolvedValue([]);
  });

  function makeApp() {
    const app = express();
    app.use(express.json());
    app.use("/api/admin/reconciliation", reconciliationRoutes);
    return app;
  }

  it("POST /api/admin/reconciliation/run returns 401 without a session", async () => {
    const app = makeApp();

    const res = await request(app).post("/api/admin/reconciliation/run");

    expect(res.status).toBe(401);
  });

  it("POST /api/admin/reconciliation/run returns 403 for a non-admin user", async () => {
    const app = makeApp();

    resolveAuthFromRequest.mockResolvedValue({
      userId: "user-1",
      sessionId: "session-1",
      mfaMethod: "TOTP",
      mfaVerifiedAt: new Date(),
    });
    prismaMock.roleAssignment.findMany.mockResolvedValue([{ roleCode: "USER" }]);

    const res = await request(app).post("/api/admin/reconciliation/run");

    expect(res.status).toBe(403);
  });

  it("POST /api/admin/reconciliation/run returns 200 for an admin with recent MFA", async () => {
    const app = makeApp();

    resolveAuthFromRequest.mockResolvedValue({
      userId: "admin-1",
      sessionId: "session-1",
      mfaMethod: "TOTP",
      mfaVerifiedAt: new Date(),
    });
    prismaMock.roleAssignment.findMany.mockResolvedValue([{ roleCode: "ADMIN" }]);
    runReconciliation.mockResolvedValue([
      { check: "GLOBAL_BALANCE:USD", ok: true },
      { check: "RECENT_TRADE_SETTLEMENT", ok: false },
    ]);

    const res = await request(app).post("/api/admin/reconciliation/run");

    expect(res.status).toBe(200);
    expect(runReconciliation).toHaveBeenCalledTimes(1);
    expect(res.body).toEqual(
      expect.objectContaining({
        ok: false,
        resultCount: 2,
        failureCount: 1,
      }),
    );
  });
});
