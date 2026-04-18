import express from "express";
import request from "supertest";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { listPersistedMatchingEvents } = vi.hoisted(() => ({
  listPersistedMatchingEvents: vi.fn(),
}));

vi.mock("../src/lib/matching/matching-events", async () => {
  const actual = await vi.importActual<any>("../src/lib/matching/matching-events");
  return {
    ...actual,
    listPersistedMatchingEvents,
  };
});

import matchingEventsRoutes from "../src/routes/matching-events";

describe("matching event replay routes", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    listPersistedMatchingEvents.mockResolvedValue([
      {
        id: 11,
        type: "ORDER_ACCEPTED",
        ts: "2026-01-01T00:00:00.000Z",
        symbol: "BTC-USD",
        mode: "PAPER",
        engine: "IN_MEMORY_MATCHER",
        source: "HUMAN",
        payload: { orderId: "11" },
      },
    ]);
  });

  it("returns durable replay events filtered by symbol/mode/event id", async () => {
    const app = express();
    app.use("/api/market/events", matchingEventsRoutes);

    const response = await request(app)
      .get("/api/market/events/replay")
      .query({ symbol: "BTC-USD", mode: "PAPER", afterEventId: "10", limit: "25" });

    expect(response.status).toBe(200);
    expect(response.body.ok).toBe(true);
    expect(response.body.events).toHaveLength(1);
    expect(listPersistedMatchingEvents).toHaveBeenCalledWith({
      symbol: "BTC-USD",
      mode: "PAPER",
      afterEventId: 10,
      limit: 25,
    });
  });
});
