import { beforeEach, describe, expect, it, vi } from "vitest";

const { prismaMock } = vi.hoisted(() => ({
  prismaMock: {
    matchingEvent: {
      upsert: vi.fn(),
      findMany: vi.fn(),
    },
  },
}));

vi.mock("../src/lib/prisma", () => ({
  prisma: prismaMock,
}));

import {
  listPersistedMatchingEvents,
  persistMatchingEventEnvelope,
  persistMatchingEventEnvelopes,
} from "../src/lib/matching/matching-events";

describe("matching event persistence", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("persists event envelopes idempotently by eventId", async () => {
    prismaMock.matchingEvent.upsert.mockResolvedValue({
      eventId: 7,
      type: "ORDER_ACCEPTED",
      ts: new Date("2026-01-01T00:00:00.000Z"),
      symbol: "BTC-USD",
      mode: "PAPER",
      engine: "IN_MEMORY_MATCHER",
      source: "HUMAN",
      payload: { orderId: "1" },
    });

    const persisted = await persistMatchingEventEnvelope({
      id: 7,
      type: "ORDER_ACCEPTED",
      ts: "2026-01-01T00:00:00.000Z",
      symbol: "BTC-USD",
      mode: "PAPER",
      engine: "IN_MEMORY_MATCHER",
      source: "HUMAN",
      payload: { orderId: "1" },
    });

    expect(prismaMock.matchingEvent.upsert).toHaveBeenCalledTimes(1);
    expect(prismaMock.matchingEvent.upsert.mock.calls[0][0].where).toEqual({ eventId: 7 });
    expect(persisted.id).toBe(7);
  });

  it("persists multiple event envelopes and replays them with filters", async () => {
    prismaMock.matchingEvent.upsert
      .mockResolvedValueOnce({
        eventId: 8,
        type: "ORDER_RESTED",
        ts: new Date("2026-01-01T00:00:01.000Z"),
        symbol: "BTC-USD",
        mode: "PAPER",
        engine: "IN_MEMORY_MATCHER",
        source: "HUMAN",
        payload: { orderId: "8" },
      })
      .mockResolvedValueOnce({
        eventId: 9,
        type: "BOOK_DELTA",
        ts: new Date("2026-01-01T00:00:02.000Z"),
        symbol: "BTC-USD",
        mode: "PAPER",
        engine: "IN_MEMORY_MATCHER",
        source: "HUMAN",
        payload: { bestBid: "100" },
      });

    await persistMatchingEventEnvelopes([
      {
        id: 8,
        type: "ORDER_RESTED",
        ts: "2026-01-01T00:00:01.000Z",
        symbol: "BTC-USD",
        mode: "PAPER",
        engine: "IN_MEMORY_MATCHER",
        source: "HUMAN",
        payload: { orderId: "8" },
      },
      {
        id: 9,
        type: "BOOK_DELTA",
        ts: "2026-01-01T00:00:02.000Z",
        symbol: "BTC-USD",
        mode: "PAPER",
        engine: "IN_MEMORY_MATCHER",
        source: "HUMAN",
        payload: { bestBid: "100" },
      },
    ]);

    prismaMock.matchingEvent.findMany.mockResolvedValue([
      {
        eventId: 9,
        type: "BOOK_DELTA",
        ts: new Date("2026-01-01T00:00:02.000Z"),
        symbol: "BTC-USD",
        mode: "PAPER",
        engine: "IN_MEMORY_MATCHER",
        source: "HUMAN",
        payload: { bestBid: "100" },
      },
    ]);

    const replayed = await listPersistedMatchingEvents({
      symbol: "BTC-USD",
      mode: "PAPER",
      afterEventId: 8,
      limit: 10,
    });

    expect(prismaMock.matchingEvent.findMany).toHaveBeenCalledTimes(1);
    expect(prismaMock.matchingEvent.findMany.mock.calls[0][0].where).toEqual({
      eventId: { gt: 8 },
      symbol: "BTC-USD",
      mode: "PAPER",
    });
    expect(replayed).toHaveLength(1);
    expect(replayed[0]?.id).toBe(9);
  });
});
