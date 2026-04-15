import express from "express";
import request from "supertest";
import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  prismaMock,
  recordSecurityAudit,
  resolveAuthFromRequest,
  reserveOrderOnPlacement,
  executeLimitOrderAgainstBook,
  reconcileOrderExecution,
  getOrderRemainingQty,
  releaseOrderOnCancel,
} = vi.hoisted(() => ({
  prismaMock: {
    roleAssignment: { findMany: vi.fn() },
    kycCase: { findFirst: vi.fn() },
    order: { findMany: vi.fn(), findUnique: vi.fn() },
    market: { findUnique: vi.fn() },
    $transaction: vi.fn(),
  },
  recordSecurityAudit: vi.fn(),
  resolveAuthFromRequest: vi.fn(),
  reserveOrderOnPlacement: vi.fn(),
  executeLimitOrderAgainstBook: vi.fn(),
  reconcileOrderExecution: vi.fn(),
  getOrderRemainingQty: vi.fn(),
  releaseOrderOnCancel: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/service/security-audit", () => ({ recordSecurityAudit }));
vi.mock("../src/modules/auth/auth.service", () => ({
  authService: { resolveAuthFromRequest },
}));
vi.mock("../src/lib/ledger", () => ({
  reserveOrderOnPlacement,
  executeLimitOrderAgainstBook,
  reconcileOrderExecution,
  getOrderRemainingQty,
  releaseOrderOnCancel,
}));
vi.mock("../src/middleware/audit-privileged", () => ({
  auditPrivilegedRequest: () => (_req: any, _res: any, next: (err?: unknown) => void) => next(),
}));
vi.mock("../src/middleware/simple-rate-limit", () => ({
  simpleRateLimit: () => (_req: any, _res: any, next: (err?: unknown) => void) => next(),
}));

import ordersRoutes from "../src/routes/orders";

describe("orders routes", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    resolveAuthFromRequest.mockResolvedValue(null);
    prismaMock.roleAssignment.findMany.mockResolvedValue([]);
    prismaMock.kycCase.findFirst.mockResolvedValue(null);
  });

  function makeApp() {
    const app = express();
    app.use(express.json());
    app.use("/api/orders", ordersRoutes);
    return app;
  }

  it("GET /api/orders returns 401 without a session", async () => {
    const app = makeApp();

    const res = await request(app).get("/api/orders");

    expect(res.status).toBe(401);
  });

  it("POST /api/orders returns 401 without a session", async () => {
    const app = makeApp();

    const res = await request(app)
      .post("/api/orders")
      .send({
        symbol: "BTC-USD",
        side: "BUY",
        type: "LIMIT",
        price: "100",
        qty: "1",
      });

    expect(res.status).toBe(401);
  });

  it("GET /api/orders/:id returns 401 without a session", async () => {
    const app = makeApp();

    const res = await request(app).get("/api/orders/123");

    expect(res.status).toBe(401);
  });
});
