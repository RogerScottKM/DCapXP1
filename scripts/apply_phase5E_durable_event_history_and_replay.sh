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
schema_path = root / "apps/api/prisma/schema.prisma"
migration_dir = root / "apps/api/prisma/migrations/20260418_phase5e_matching_event_history"
migration_path = migration_dir / "migration.sql"
events_path = root / "apps/api/src/lib/matching/matching-events.ts"
submit_path = root / "apps/api/src/lib/matching/submit-limit-order.ts"
route_path = root / "apps/api/src/routes/matching-events.ts"
test_persist_path = root / "apps/api/test/matching-events.persistence.test.ts"
test_replay_path = root / "apps/api/test/matching-events.replay.routes.test.ts"

for p in [pkg_path, schema_path, events_path, submit_path, route_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:matching:durable-events"] = "vitest run test/matching-events.persistence.test.ts test/matching-events.replay.routes.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

schema_text = schema_path.read_text()
if "model MatchingEvent {" not in schema_text:
    schema_text = schema_text.rstrip() + "\n\n" + dedent("""model MatchingEvent {
  id        BigInt   @id @default(autoincrement())
  eventId   Int      @unique
  type      String
  ts        DateTime
  symbol    String
  mode      String
  engine    String
  source    String
  payload   Json
  createdAt DateTime @default(now())

  @@index([symbol, mode, eventId])
}
""")
schema_path.write_text(schema_text)

migration_dir.mkdir(parents=True, exist_ok=True)
migration_path.write_text(dedent("""-- Phase 5E durable event history
CREATE TABLE "MatchingEvent" (
  "id" BIGSERIAL PRIMARY KEY,
  "eventId" INTEGER NOT NULL UNIQUE,
  "type" TEXT NOT NULL,
  "ts" TIMESTAMP(3) NOT NULL,
  "symbol" TEXT NOT NULL,
  "mode" TEXT NOT NULL,
  "engine" TEXT NOT NULL,
  "source" TEXT NOT NULL,
  "payload" JSONB NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX "MatchingEvent_symbol_mode_eventId_idx"
  ON "MatchingEvent" ("symbol", "mode", "eventId");
"""))

events_path.write_text(dedent("""import { Prisma, type PrismaClient } from "@prisma/client";
import { Decimal } from "@prisma/client/runtime/library";

import { prisma } from "../prisma";

type MatchingEventType =
  | "ORDER_ACCEPTED"
  | "ORDER_FILL"
  | "ORDER_PARTIALLY_FILLED"
  | "ORDER_FILLED"
  | "ORDER_RESTED"
  | "ORDER_CANCELLED"
  | "BOOK_DELTA"
  | "RUNTIME_STATUS"
  | "RECONCILIATION_RESULT";

export type MatchingEvent = {
  type: MatchingEventType;
  ts: string;
  symbol: string;
  mode: string;
  engine: string;
  source: "HUMAN" | "AGENT" | "SYSTEM";
  payload: Record<string, unknown>;
};

export type MatchingEventEnvelope = MatchingEvent & {
  id: number;
};

type MatchingEventListener = (event: MatchingEventEnvelope) => void;
type PersistDb = PrismaClient | Prisma.TransactionClient | any;

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

function toEnvelope(record: any): MatchingEventEnvelope {
  return {
    id: Number(record.eventId),
    type: record.type,
    ts: record.ts instanceof Date ? record.ts.toISOString() : String(record.ts),
    symbol: String(record.symbol),
    mode: String(record.mode),
    engine: String(record.engine),
    source: record.source as MatchingEvent["source"],
    payload: (record.payload ?? {}) as Record<string, unknown>,
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

export async function persistMatchingEventEnvelope(
  envelope: MatchingEventEnvelope,
  db: PersistDb = prisma,
): Promise<MatchingEventEnvelope> {
  const record = await db.matchingEvent.upsert({
    where: { eventId: envelope.id },
    update: {
      type: envelope.type,
      ts: new Date(envelope.ts),
      symbol: envelope.symbol,
      mode: envelope.mode,
      engine: envelope.engine,
      source: envelope.source,
      payload: envelope.payload as any,
    },
    create: {
      eventId: envelope.id,
      type: envelope.type,
      ts: new Date(envelope.ts),
      symbol: envelope.symbol,
      mode: envelope.mode,
      engine: envelope.engine,
      source: envelope.source,
      payload: envelope.payload as any,
    },
  });

  return toEnvelope(record);
}

export async function persistMatchingEventEnvelopes(
  envelopes: MatchingEventEnvelope[],
  db: PersistDb = prisma,
): Promise<MatchingEventEnvelope[]> {
  const persisted: MatchingEventEnvelope[] = [];
  for (const envelope of envelopes) {
    persisted.push(await persistMatchingEventEnvelope(envelope, db));
  }
  return persisted;
}

export async function listPersistedMatchingEvents(
  input: {
    afterEventId?: number | null;
    symbol?: string | null;
    mode?: string | null;
    limit?: number;
  } = {},
  db: PersistDb = prisma,
): Promise<MatchingEventEnvelope[]> {
  const records = await db.matchingEvent.findMany({
    where: {
      ...(input.afterEventId != null ? { eventId: { gt: input.afterEventId } } : {}),
      ...(input.symbol ? { symbol: input.symbol } : {}),
      ...(input.mode ? { mode: input.mode } : {}),
    },
    orderBy: { eventId: "asc" },
    take: input.limit ?? 100,
  });

  return records.map(toEnvelope);
}

export function listMatchingEvents(limit = 100): MatchingEventEnvelope[] {
  return matchingEvents.slice(-limit);
}

export function getMatchingEventCount(): number {
  return matchingEvents.length;
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
if 'persistMatchingEventEnvelopes' not in submit_text:
    submit_text = submit_text.replace(
        'import { buildMatchingEventsFromSubmission, emitMatchingEvents } from "./matching-events";',
        'import { buildMatchingEventsFromSubmission, emitMatchingEvents, persistMatchingEventEnvelopes } from "./matching-events";',
        1,
    )

if 'await persistMatchingEventEnvelopes(emittedEvents, tx as any);' not in submit_text:
    submit_text = submit_text.replace(
        '    const emittedEvents = emitMatchingEvents(events);\n',
        '    const emittedEvents = emitMatchingEvents(events);\n    await persistMatchingEventEnvelopes(emittedEvents, tx as any);\n',
        1,
    )

submit_path.write_text(submit_text)

route_text = route_path.read_text()
if 'listPersistedMatchingEvents' not in route_text:
    route_text = route_text.replace(
        '  listMatchingEvents,\n  subscribeMatchingEvents,\n} from "../lib/matching/matching-events";',
        '  listMatchingEvents,\n  listPersistedMatchingEvents,\n  subscribeMatchingEvents,\n} from "../lib/matching/matching-events";',
        1,
    )

if 'router.get("/replay"' not in route_text:
    replay_block = dedent("""\

router.get("/replay", async (req, res) => {
  const symbol = typeof req.query.symbol === "string" ? req.query.symbol : undefined;
  const mode = typeof req.query.mode === "string" ? req.query.mode : undefined;
  const afterEventId =
    typeof req.query.afterEventId === "string" && req.query.afterEventId.length > 0
      ? Number(req.query.afterEventId)
      : undefined;
  const limit =
    typeof req.query.limit === "string" && req.query.limit.length > 0
      ? Number(req.query.limit)
      : 100;

  const events = await listPersistedMatchingEvents({
    symbol,
    mode,
    afterEventId: Number.isFinite(afterEventId) ? afterEventId : undefined,
    limit: Number.isFinite(limit) ? limit : 100,
  });

  return res.json({ ok: true, events });
});
""")
    export_anchor = "\nexport default router;\n"
    if export_anchor not in route_text:
        raise SystemExit("Could not find export anchor in matching-events.ts route")
    route_text = route_text.replace(export_anchor, replay_block + export_anchor, 1)

route_path.write_text(route_text)

test_persist_path.write_text(dedent("""import { beforeEach, describe, expect, it, vi } from "vitest";

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
"""))

test_replay_path.write_text(dedent("""import express from "express";
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
"""))

print("Patched package.json, added MatchingEvent schema + migration, upgraded matching-events.ts with durable persistence + replay helpers, patched submit-limit-order.ts and matching-events route for replay, and wrote focused Phase 5E tests.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 5E patch applied."
