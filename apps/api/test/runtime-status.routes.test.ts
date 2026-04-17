import express from "express";
import request from "supertest";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { getRuntimeStatus } = vi.hoisted(() => ({
  getRuntimeStatus: vi.fn(),
}));

vi.mock("../src/lib/runtime/runtime-status", () => ({
  getRuntimeStatus,
}));

vi.mock("../src/middleware/require-auth", () => ({
  requireAuth: (req: any, res: any, next: any) => {
    if (req.headers["x-auth"] === "1") return next();
    return res.status(401).json({ error: "UNAUTHENTICATED" });
  },
  requireAdminRecentMfa: () => (req: any, res: any, next: any) => {
    if (req.headers["x-admin"] === "1") return next();
    return res.status(403).json({ error: "FORBIDDEN" });
  },
}));

import runtimeStatusRoutes from "../src/routes/runtime-status";

describe("runtime status routes", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    getRuntimeStatus.mockReturnValue({
      started: true,
      startedAt: "2026-01-01T00:00:00.000Z",
      stoppedAt: null,
      stopReason: null,
      port: 4010,
      reconciliationEnabled: true,
      reconciliationIntervalMs: 60000,
      lastReconciliationAt: "2026-01-01T00:01:00.000Z",
      lastReconciliationOk: true,
      lastReconciliationFailureCount: 0,
      lastReconciliationCheckCount: 4,
      activeSerializedLanes: 0,
      matchingEventCount: 5,
      lastEventId: 5,
    });
  });

  it("returns 401 without an authenticated session", async () => {
    const app = express();
    app.use("/api/admin/runtime-status", runtimeStatusRoutes);

    const response = await request(app).get("/api/admin/runtime-status");

    expect(response.status).toBe(401);
  });

  it("returns 403 for a non-admin request", async () => {
    const app = express();
    app.use("/api/admin/runtime-status", runtimeStatusRoutes);

    const response = await request(app)
      .get("/api/admin/runtime-status")
      .set("x-auth", "1");

    expect(response.status).toBe(403);
  });

  it("returns the runtime status snapshot for an admin with recent MFA", async () => {
    const app = express();
    app.use("/api/admin/runtime-status", runtimeStatusRoutes);

    const response = await request(app)
      .get("/api/admin/runtime-status")
      .set("x-auth", "1")
      .set("x-admin", "1");

    expect(response.status).toBe(200);
    expect(response.body.ok).toBe(true);
    expect(response.body.status.port).toBe(4010);
    expect(getRuntimeStatus).toHaveBeenCalledTimes(1);
  });
});
