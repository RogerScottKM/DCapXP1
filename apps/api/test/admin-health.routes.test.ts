import express from "express";
import request from "supertest";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { getRuntimeStatus, getMatchingEventListenerCount, listMatchingEvents } = vi.hoisted(() => ({
  getRuntimeStatus: vi.fn(),
  getMatchingEventListenerCount: vi.fn(),
  listMatchingEvents: vi.fn(),
}));

vi.mock("../src/lib/runtime/runtime-status", () => ({
  getRuntimeStatus,
}));

vi.mock("../src/lib/matching/matching-events", () => ({
  getMatchingEventListenerCount,
  listMatchingEvents,
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

import adminHealthRoutes from "../src/routes/admin-health";

describe("admin health routes", () => {
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
      lastReconciliationOk: false,
      lastReconciliationFailureCount: 1,
      lastReconciliationCheckCount: 4,
      activeSerializedLanes: 2,
      matchingEventCount: 17,
      lastEventId: 17,
    });
    getMatchingEventListenerCount.mockReturnValue(3);
    listMatchingEvents.mockReturnValue([
      { id: 16, type: "RUNTIME_STATUS", payload: { status: "STARTED" } },
      { id: 17, type: "RECONCILIATION_RESULT", payload: { ok: false, failureCount: 1, checkCount: 4 } },
    ]);
  });

  it("returns 401 without an authenticated session", async () => {
    const app = express();
    app.use("/api/admin/health", adminHealthRoutes);

    const response = await request(app).get("/api/admin/health");

    expect(response.status).toBe(401);
  });

  it("returns 403 for a non-admin request", async () => {
    const app = express();
    app.use("/api/admin/health", adminHealthRoutes);

    const response = await request(app)
      .get("/api/admin/health")
      .set("x-auth", "1");

    expect(response.status).toBe(403);
  });

  it("returns admin health including runtime and subscriber metrics", async () => {
    const app = express();
    app.use("/api/admin/health", adminHealthRoutes);

    const response = await request(app)
      .get("/api/admin/health")
      .set("x-auth", "1")
      .set("x-admin", "1");

    expect(response.status).toBe(200);
    expect(response.body.ok).toBe(true);
    expect(response.body.health.activeSerializedLanes).toBe(2);
    expect(response.body.health.subscriberCount).toBe(3);
    expect(response.body.health.lastReconciliation.failureCount).toBe(1);
  });
});
