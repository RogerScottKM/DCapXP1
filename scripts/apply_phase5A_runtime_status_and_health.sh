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
import sys
from textwrap import dedent

root = Path(sys.argv[1])

pkg_path = root / "apps/api/package.json"
events_path = root / "apps/api/src/lib/matching/matching-events.ts"
runtime_dir = root / "apps/api/src/lib/runtime"
runtime_path = runtime_dir / "runtime-status.ts"
worker_path = root / "apps/api/src/workers/reconciliation.ts"
server_path = root / "apps/api/src/server.ts"
route_path = root / "apps/api/src/routes/runtime-status.ts"
app_path = root / "apps/api/src/app.ts"
test_lib_path = root / "apps/api/test/runtime-status.lib.test.ts"
test_route_path = root / "apps/api/test/runtime-status.routes.test.ts"

for p in [pkg_path, events_path, worker_path, server_path, app_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:runtime:status"] = "vitest run test/runtime-status.lib.test.ts test/runtime-status.routes.test.ts"
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

runtime_dir.mkdir(parents=True, exist_ok=True)
runtime_path.write_text(dedent("""\
import { emitMatchingEvent, getMatchingEventCount, listMatchingEvents } from "../matching/matching-events";
import { getSerializedLaneCount } from "../matching/serialized-dispatch";

type ReconciliationResultLike = {
  check: string;
  ok: boolean;
  details?: Record<string, unknown>;
};

type RuntimeStatusState = {
  started: boolean;
  startedAt: string | null;
  stoppedAt: string | null;
  stopReason: string | null;
  port: number | null;
  reconciliationEnabled: boolean;
  reconciliationIntervalMs: number | null;
  lastReconciliationAt: string | null;
  lastReconciliationOk: boolean | null;
  lastReconciliationFailureCount: number;
  lastReconciliationCheckCount: number;
};

const runtimeState: RuntimeStatusState = {
  started: false,
  startedAt: null,
  stoppedAt: null,
  stopReason: null,
  port: null,
  reconciliationEnabled: false,
  reconciliationIntervalMs: null,
  lastReconciliationAt: null,
  lastReconciliationOk: null,
  lastReconciliationFailureCount: 0,
  lastReconciliationCheckCount: 0,
};

export type RuntimeStatusSnapshot = RuntimeStatusState & {
  activeSerializedLanes: number;
  matchingEventCount: number;
  lastEventId: number | null;
};

function snapshot(): RuntimeStatusSnapshot {
  const recentEvents = listMatchingEvents(1000);
  return {
    ...runtimeState,
    activeSerializedLanes: getSerializedLaneCount(),
    matchingEventCount: getMatchingEventCount(),
    lastEventId: recentEvents.length > 0 ? recentEvents[recentEvents.length - 1]!.id : null,
  };
}

export function markRuntimeStarted(input: {
  port: number;
  reconciliationEnabled: boolean;
  reconciliationIntervalMs: number;
}): RuntimeStatusSnapshot {
  runtimeState.started = true;
  runtimeState.startedAt = new Date().toISOString();
  runtimeState.stoppedAt = null;
  runtimeState.stopReason = null;
  runtimeState.port = input.port;
  runtimeState.reconciliationEnabled = input.reconciliationEnabled;
  runtimeState.reconciliationIntervalMs = input.reconciliationIntervalMs;

  const current = snapshot();
  emitMatchingEvent({
    type: "RUNTIME_STATUS",
    ts: new Date().toISOString(),
    symbol: "__SYSTEM__",
    mode: "SYSTEM",
    engine: "SYSTEM",
    source: "SYSTEM",
    payload: {
      status: "STARTED",
      runtime: current,
    },
  });
  return snapshot();
}

export function markRuntimeStopped(reason: string): RuntimeStatusSnapshot {
  runtimeState.started = false;
  runtimeState.stoppedAt = new Date().toISOString();
  runtimeState.stopReason = reason;

  const current = snapshot();
  emitMatchingEvent({
    type: "RUNTIME_STATUS",
    ts: new Date().toISOString(),
    symbol: "__SYSTEM__",
    mode: "SYSTEM",
    engine: "SYSTEM",
    source: "SYSTEM",
    payload: {
      status: "STOPPED",
      reason,
      runtime: current,
    },
  });
  return snapshot();
}

export function noteReconciliationRun(results: ReconciliationResultLike[]): RuntimeStatusSnapshot {
  const failures = results.filter((result) => !result.ok);

  runtimeState.lastReconciliationAt = new Date().toISOString();
  runtimeState.lastReconciliationOk = failures.length === 0;
  runtimeState.lastReconciliationFailureCount = failures.length;
  runtimeState.lastReconciliationCheckCount = results.length;

  const current = snapshot();
  emitMatchingEvent({
    type: "RECONCILIATION_RESULT",
    ts: runtimeState.lastReconciliationAt,
    symbol: "__SYSTEM__",
    mode: "SYSTEM",
    engine: "SYSTEM",
    source: "SYSTEM",
    payload: {
      ok: runtimeState.lastReconciliationOk,
      failureCount: runtimeState.lastReconciliationFailureCount,
      checkCount: runtimeState.lastReconciliationCheckCount,
      failures: failures.slice(0, 10),
      runtime: current,
    },
  });

  return snapshot();
}

export function getRuntimeStatus(): RuntimeStatusSnapshot {
  return snapshot();
}

export function resetRuntimeStatusForTests(): void {
  runtimeState.started = false;
  runtimeState.startedAt = null;
  runtimeState.stoppedAt = null;
  runtimeState.stopReason = null;
  runtimeState.port = null;
  runtimeState.reconciliationEnabled = false;
  runtimeState.reconciliationIntervalMs = null;
  runtimeState.lastReconciliationAt = null;
  runtimeState.lastReconciliationOk = null;
  runtimeState.lastReconciliationFailureCount = 0;
  runtimeState.lastReconciliationCheckCount = 0;
}
"""))

worker_text = worker_path.read_text()
if 'import { noteReconciliationRun } from "../lib/runtime/runtime-status";' not in worker_text:
    anchor = 'import { recordSecurityAudit } from "../lib/service/security-audit";'
    if anchor not in worker_text:
        raise SystemExit("Could not find security-audit import anchor in reconciliation.ts")
    worker_text = worker_text.replace(anchor, anchor + '\nimport { noteReconciliationRun } from "../lib/runtime/runtime-status";', 1)
if 'noteReconciliationRun(allResults);' not in worker_text:
    worker_text = worker_text.replace('\n  return allResults;\n}', '\n  noteReconciliationRun(allResults);\n  return allResults;\n}', 1)
worker_path.write_text(worker_text)

server_text = server_path.read_text()
if 'import { markRuntimeStarted, markRuntimeStopped } from "./lib/runtime/runtime-status";' not in server_text:
    anchor = 'import {\n  startReconciliationWorker,\n  stopReconciliationWorker,\n} from "./workers/reconciliation";'
    if anchor not in server_text:
        raise SystemExit("Could not find reconciliation import anchor in server.ts")
    server_text = server_text.replace(anchor, anchor + '\nimport { markRuntimeStarted, markRuntimeStopped } from "./lib/runtime/runtime-status";', 1)
if 'markRuntimeStopped(signal);' not in server_text:
    server_text = server_text.replace('  stopReconciliationWorker();\n', '  stopReconciliationWorker();\n  markRuntimeStopped(signal);\n', 1)
if 'markRuntimeStarted({' not in server_text:
    server_text = server_text.replace(
        '    if (reconEnabled) {\n      startReconciliationWorker(RECON_INTERVAL_MS);\n    }\n',
        '    if (reconEnabled) {\n      startReconciliationWorker(RECON_INTERVAL_MS);\n    }\n\n    markRuntimeStarted({\n      port: PORT,\n      reconciliationEnabled: reconEnabled,\n      reconciliationIntervalMs: RECON_INTERVAL_MS,\n    });\n',
        1,
    )
server_path.write_text(server_text)

route_path.write_text(dedent("""\
import { Router } from "express";

import { getRuntimeStatus } from "../lib/runtime/runtime-status";
import { requireAuth, requireAdminRecentMfa } from "../middleware/require-auth";

const router = Router();

router.use(requireAuth);

router.get("/", requireAdminRecentMfa(), (_req, res) => {
  return res.json({
    ok: true,
    status: getRuntimeStatus(),
  });
});

export default router;
"""))

app_text = app_path.read_text()
if 'import runtimeStatusRoutes from "./routes/runtime-status";' not in app_text:
    anchor = None
    for candidate in [
        'import matchingEventsRoutes from "./routes/matching-events";',
        'import reconciliationRoutes from "./routes/reconciliation";',
        'import ordersRoutes from "./routes/orders";',
    ]:
        if candidate in app_text:
            anchor = candidate
            break
    if anchor is None:
        raise SystemExit("Could not find route import anchor in app.ts")
    app_text = app_text.replace(anchor, anchor + '\nimport runtimeStatusRoutes from "./routes/runtime-status";', 1)
if 'app.use("/api/admin/runtime-status", runtimeStatusRoutes);' not in app_text:
    export_anchor = 'export default app;'
    if export_anchor not in app_text:
        raise SystemExit("Could not find export anchor in app.ts")
    mount_block = '\n// ── Runtime status routes ─────────────────────────────────\napp.use("/api/admin/runtime-status", runtimeStatusRoutes);\n'
    app_text = app_text.replace(export_anchor, mount_block + '\n' + export_anchor, 1)
app_path.write_text(app_text)

test_lib_path.write_text(dedent("""\
import { beforeEach, describe, expect, it } from "vitest";

import { listMatchingEvents, resetMatchingEventsForTests } from "../src/lib/matching/matching-events";
import { resetSerializedDispatchForTests } from "../src/lib/matching/serialized-dispatch";
import {
  markRuntimeStarted,
  markRuntimeStopped,
  noteReconciliationRun,
  resetRuntimeStatusForTests,
} from "../src/lib/runtime/runtime-status";

describe("runtime status library", () => {
  beforeEach(() => {
    resetMatchingEventsForTests();
    resetSerializedDispatchForTests();
    resetRuntimeStatusForTests();
  });

  it("tracks runtime start and stop with status snapshots", () => {
    const started = markRuntimeStarted({
      port: 4010,
      reconciliationEnabled: true,
      reconciliationIntervalMs: 60000,
    });

    expect(started.started).toBe(true);
    expect(started.port).toBe(4010);
    expect(started.reconciliationEnabled).toBe(true);
    expect(started.matchingEventCount).toBe(1);

    const stopped = markRuntimeStopped("SIGTERM");

    expect(stopped.started).toBe(false);
    expect(stopped.stopReason).toBe("SIGTERM");
    expect(stopped.matchingEventCount).toBe(2);

    const eventTypes = listMatchingEvents().map((event) => event.type);
    expect(eventTypes).toEqual(["RUNTIME_STATUS", "RUNTIME_STATUS"]);
  });

  it("records reconciliation summaries and emits a reconciliation runtime event", () => {
    markRuntimeStarted({
      port: 4010,
      reconciliationEnabled: true,
      reconciliationIntervalMs: 60000,
    });

    const status = noteReconciliationRun([
      { check: "GLOBAL_BALANCE", ok: true },
      { check: "ORDER_STATUS_CONSISTENCY", ok: false, details: { mismatch: 1 } },
    ]);

    expect(status.lastReconciliationOk).toBe(false);
    expect(status.lastReconciliationFailureCount).toBe(1);
    expect(status.lastReconciliationCheckCount).toBe(2);

    const events = listMatchingEvents();
    expect(events[events.length - 1]?.type).toBe("RECONCILIATION_RESULT");
  });
});
"""))

test_route_path.write_text(dedent("""\
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
"""))

print("Patched package.json, added runtime-status.ts, wired reconciliation/server lifecycle into runtime status, mounted /api/admin/runtime-status, and wrote runtime-status focused tests for Phase 5A.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 5A patch applied."
