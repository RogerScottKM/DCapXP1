#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 1 && -n "${1:-}" ]]; then
  ROOT="$1"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import re
import sys
from textwrap import dedent

root = Path(sys.argv[1])

pkg_path = root / "apps/api/package.json"
events_path = root / "apps/api/src/lib/matching/matching-events.ts"
submit_path = root / "apps/api/src/lib/matching/submit-limit-order.ts"
index_path = root / "apps/api/src/lib/matching/index.ts"
route_path = root / "apps/api/src/routes/matching-events.ts"
app_path = root / "apps/api/src/app.ts"
test_path = root / "apps/api/test/matching-events.stream.test.ts"

for p in [pkg_path, events_path, submit_path, index_path, app_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:matching:stream"] = "vitest run test/matching-events.stream.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

events_path.write_text(dedent("""\
import { Decimal } from "@prisma/client/runtime/library";

type MatchingEventType =
  | "ORDER_ACCEPTED"
  | "ORDER_FILL"
  | "ORDER_PARTIALLY_FILLED"
  | "ORDER_FILLED"
  | "ORDER_RESTED"
  | "ORDER_CANCELLED"
  | "BOOK_DELTA";

export type MatchingEvent = {
  type: MatchingEventType;
  ts: string;
  symbol: string;
  mode: string;
  engine: string;
  source: "HUMAN" | "AGENT";
  payload: Record<string, unknown>;
};

export type MatchingEventEnvelope = MatchingEvent & {
  id: number;
};

type MatchingEventListener = (event: MatchingEventEnvelope) => void;

const matchingEvents: MatchingEventEnvelope[] = [];
const listeners = new Set<MatchingEventListener>();
let nextEventId = 1;

function isZeroLike(value: unknown): boolean {
  if (value === null || value === undefined) return false;
  try {
    return new Decimal(String(value)).eq(0);
  } catch {
    return false;
  }
}

function normalizeFillPayload(fill: any): Record<string, unknown> {
  if (fill?.trade) {
    return {
      tradeId: String(fill.trade.id),
      qty: String(fill.trade.qty),
      price: String(fill.trade.price),
      buyOrderId: fill.trade.buyOrderId != null ? String(fill.trade.buyOrderId) : undefined,
      sellOrderId: fill.trade.sellOrderId != null ? String(fill.trade.sellOrderId) : undefined,
    };
  }

  return {
    makerOrderId: fill?.makerOrderId != null ? String(fill.makerOrderId) : undefined,
    takerOrderId: fill?.takerOrderId != null ? String(fill.takerOrderId) : undefined,
    qty: fill?.qty != null ? String(fill.qty) : undefined,
    price: fill?.price != null ? String(fill.price) : undefined,
  };
}

export function emitMatchingEvent(event: MatchingEvent): MatchingEventEnvelope {
  const envelope: MatchingEventEnvelope = {
    ...event,
    id: nextEventId++,
  };
  matchingEvents.push(envelope);
  for (const listener of listeners) {
    try {
      listener(envelope);
    } catch {
      // listener failures must not break event publication
    }
  }
  return envelope;
}

export function emitMatchingEvents(events: MatchingEvent[]): MatchingEventEnvelope[] {
  return events.map((event) => emitMatchingEvent(event));
}

export function listMatchingEvents(limit = 100): MatchingEventEnvelope[] {
  return matchingEvents.slice(-limit);
}

export function subscribeMatchingEvents(listener: MatchingEventListener): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function getMatchingEventListenerCount(): number {
  return listeners.size;
}

export function resetMatchingEventsForTests(): void {
  matchingEvents.length = 0;
  listeners.clear();
  nextEventId = 1;
}

export function buildMatchingEventsFromSubmission(input: {
  order: any;
  execution: any;
  engine: string;
  source: "HUMAN" | "AGENT";
  timeInForce: string;
}): MatchingEvent[] {
  const ts = new Date().toISOString();
  const order = input.order;
  const execution = input.execution ?? {};
  const events: MatchingEvent[] = [
    {
      type: "ORDER_ACCEPTED",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: {
        orderId: String(order.id),
        side: String(order.side),
        price: String(order.price),
        qty: String(order.qty),
        timeInForce: input.timeInForce,
      },
    },
  ];

  const fills = Array.isArray(execution.fills) ? execution.fills : [];
  for (const fill of fills) {
    events.push({
      type: "ORDER_FILL",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: normalizeFillPayload(fill),
    });
  }

  if (fills.length > 0) {
    events.push({
      type: isZeroLike(execution.remainingQty) ? "ORDER_FILLED" : "ORDER_PARTIALLY_FILLED",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: {
        orderId: String(order.id),
        remainingQty: execution.remainingQty != null ? String(execution.remainingQty) : undefined,
        fillCount: fills.length,
      },
    });
  }

  if (execution.restingOrderId) {
    events.push({
      type: "ORDER_RESTED",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: {
        orderId: String(execution.restingOrderId),
        remainingQty: execution.remainingQty != null ? String(execution.remainingQty) : undefined,
      },
    });
  }

  if (execution.tifAction === "CANCEL_REMAINDER" || String(execution.order?.status ?? order.status) === "CANCELLED") {
    events.push({
      type: "ORDER_CANCELLED",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: {
        orderId: String(order.id),
        remainingQty: execution.remainingQty != null ? String(execution.remainingQty) : undefined,
        reason: execution.tifAction === "CANCEL_REMAINDER" ? "TIF_CANCEL_REMAINDER" : "CANCELLED",
      },
    });
  }

  if (execution.bookDelta) {
    events.push({
      type: "BOOK_DELTA",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: execution.bookDelta,
    });
  }

  return events;
}
"""))

submit_text = submit_path.read_text()
submit_text = submit_text.replace(
    '    const events = buildMatchingEventsFromSubmission({',
    '    const events = buildMatchingEventsFromSubmission({',
    1,
)
submit_text = submit_text.replace(
    '    emitMatchingEvents(events);\n',
    '    const emittedEvents = emitMatchingEvents(events);\n',
    1,
)
submit_text = submit_text.replace(
    '      events,\n',
    '      events: emittedEvents,\n',
    1,
)
submit_path.write_text(submit_text)

route_path.write_text(dedent("""\
import express from "express";

import {
  type MatchingEventEnvelope,
  listMatchingEvents,
  subscribeMatchingEvents,
} from "../lib/matching/matching-events";

const router = express.Router();

function matchesFilter(
  event: MatchingEventEnvelope,
  symbol?: string,
  mode?: string,
): boolean {
  if (symbol && event.symbol !== symbol) return false;
  if (mode && event.mode !== mode) return false;
  return true;
}

export function buildSseEventFrame(event: MatchingEventEnvelope): string {
  return `id: ${event.id}\nevent: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`;
}

router.get("/recent", (req, res) => {
  const symbol = typeof req.query.symbol === "string" ? req.query.symbol : undefined;
  const mode = typeof req.query.mode === "string" ? req.query.mode : undefined;
  const events = listMatchingEvents(200).filter((event) => matchesFilter(event, symbol, mode));
  return res.json({ ok: true, events });
});

router.get("/stream", (req, res) => {
  const symbol = typeof req.query.symbol === "string" ? req.query.symbol : undefined;
  const mode = typeof req.query.mode === "string" ? req.query.mode : undefined;

  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.setHeader("X-Accel-Buffering", "no");
  if (typeof (res as any).flushHeaders === "function") {
    (res as any).flushHeaders();
  }

  const snapshot = listMatchingEvents(200).filter((event) => matchesFilter(event, symbol, mode));
  res.write(`event: snapshot\ndata: ${JSON.stringify({ events: snapshot })}\n\n`);

  const unsubscribe = subscribeMatchingEvents((event) => {
    if (!matchesFilter(event, symbol, mode)) return;
    res.write(buildSseEventFrame(event));
  });

  const keepAlive = setInterval(() => {
    res.write(": keep-alive\n\n");
  }, 15000);

  req.on("close", () => {
    clearInterval(keepAlive);
    unsubscribe();
    res.end();
  });
});

export default router;
"""))

app_text = app_path.read_text()
if 'import matchingEventsRoutes from "./routes/matching-events";' not in app_text:
    import_anchor = None
    for candidate in [
        'import reconciliationRoutes from "./routes/reconciliation";',
        'import ordersRoutes from "./routes/orders";',
        'import tradeRoutes from "./routes/trade";',
    ]:
        if candidate in app_text:
            import_anchor = candidate
            break
    if import_anchor is None:
        raise SystemExit("Could not find route import anchor in app.ts")
    app_text = app_text.replace(
        import_anchor,
        import_anchor + '\nimport matchingEventsRoutes from "./routes/matching-events";',
        1,
    )

if 'app.use("/api/market/events", matchingEventsRoutes);' not in app_text:
    mount_block = '\n// ── Matching events stream routes ──────────────────────────\napp.use("/api/market/events", matchingEventsRoutes);\n'
    export_anchor = "export default app;"
    if export_anchor not in app_text:
        raise SystemExit("Could not find export anchor in app.ts")
    app_text = app_text.replace(export_anchor, mount_block + "\n" + export_anchor, 1)

app_path.write_text(app_text)

index_text = index_path.read_text()
export_line = 'export * from "./matching-events";'
if export_line not in index_text:
    index_text = index_text.rstrip() + "\n" + export_line + "\n"
index_path.write_text(index_text)

test_path.write_text(dedent("""\
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
"""))

print("Patched package.json, upgraded matching-events.ts with live subscriptions, added /api/market/events recent+stream routes, mounted them in app.ts, and wrote apps/api/test/matching-events.stream.test.ts for Phase 4F.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 4F patch applied."
