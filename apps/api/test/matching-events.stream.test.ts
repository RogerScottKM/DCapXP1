import express from "express";
import request from "supertest";
import { beforeEach, describe, expect, it } from "vitest";

import matchingEventsRoutes, { buildSseEventFrame } from "../src/routes/matching-events";
import {
  buildMatchingEventsFromSubmission,
  emitMatchingEvent,
  getMatchingEventListenerCount,
  listMatchingEvents,
  resetMatchingEventsForTests,
  subscribeMatchingEvents,
} from "../src/lib/matching/matching-events";
import { InMemoryOrderBook } from "../src/lib/matching/in-memory-order-book";

describe("matching event delivery foundation", () => {
  beforeEach(() => {
    resetMatchingEventsForTests();
  });

  it("matching event subscriptions receive emitted envelopes with ids", () => {
    const received: any[] = [];
    const unsubscribe = subscribeMatchingEvents((event) => {
      received.push(event);
    });

    emitMatchingEvent({
      type: "ORDER_ACCEPTED",
      ts: new Date().toISOString(),
      symbol: "BTC-USD",
      mode: "PAPER",
      engine: "IN_MEMORY_MATCHER",
      source: "HUMAN",
      payload: { orderId: "1" },
    });

    unsubscribe();

    expect(received).toHaveLength(1);
    expect(received[0].id).toBe(1);
    expect(getMatchingEventListenerCount()).toBe(0);
  });

  it("recent route returns filtered websocket-ready events", async () => {
    emitMatchingEvent({
      type: "ORDER_ACCEPTED",
      ts: new Date().toISOString(),
      symbol: "BTC-USD",
      mode: "PAPER",
      engine: "IN_MEMORY_MATCHER",
      source: "HUMAN",
      payload: { orderId: "1" },
    });
    emitMatchingEvent({
      type: "ORDER_ACCEPTED",
      ts: new Date().toISOString(),
      symbol: "ETH-USD",
      mode: "LIVE",
      engine: "DB_MATCHER",
      source: "AGENT",
      payload: { orderId: "2" },
    });

    const app = express();
    app.use("/api/market/events", matchingEventsRoutes);

    const response = await request(app)
      .get("/api/market/events/recent")
      .query({ symbol: "BTC-USD", mode: "PAPER" });

    expect(response.status).toBe(200);
    expect(response.body.ok).toBe(true);
    expect(response.body.events).toHaveLength(1);
    expect(response.body.events[0].symbol).toBe("BTC-USD");
    expect(response.body.events[0].mode).toBe("PAPER");
  });

  it("buildSseEventFrame formats websocket-ready matching events for SSE", () => {
    const frame = buildSseEventFrame({
      id: 7,
      type: "BOOK_DELTA",
      ts: new Date("2026-01-01T00:00:00Z").toISOString(),
      symbol: "BTC-USD",
      mode: "PAPER",
      engine: "IN_MEMORY_MATCHER",
      source: "HUMAN",
      payload: {
        symbol: "BTC-USD",
        bestBid: "100",
        bestAsk: null,
      },
    });

    expect(frame).toContain("id: 7");
    expect(frame).toContain("event: BOOK_DELTA");
    expect(frame).toContain('"bestBid":"100"');
  });
});
