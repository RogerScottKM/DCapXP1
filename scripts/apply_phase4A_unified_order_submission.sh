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
orders_path = root / "apps/api/src/routes/orders.ts"
trade_path = root / "apps/api/src/routes/trade.ts"

for p in [pkg_path, orders_path, trade_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:matching:submission"] = "vitest run test/order-submission-unification.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

matching_dir = root / "apps/api/src/lib/matching"
matching_dir.mkdir(parents=True, exist_ok=True)

(engine_port_path := matching_dir / "engine-port.ts").write_text(dedent("""
import type { PrismaClient, Prisma } from "@prisma/client";

type LedgerDbClient = PrismaClient | Prisma.TransactionClient;

export type MatchingEngineExecutionInput = {
  orderId: bigint | string;
  quoteFeeBps?: string;
};

export type MatchingEngineExecutionResult = {
  execution: unknown;
  orderReconciliation: unknown;
  engine: string;
};

export interface MatchingEnginePort {
  readonly name: string;
  executeLimitOrder(
    input: MatchingEngineExecutionInput,
    db: LedgerDbClient,
  ): Promise<MatchingEngineExecutionResult>;
}
"""))

(db_engine_path := matching_dir / "db-matching-engine.ts").write_text(dedent("""
import type { PrismaClient, Prisma } from "@prisma/client";

import { executeLimitOrderAgainstBook, reconcileOrderExecution } from "../ledger";
import type { MatchingEngineExecutionInput, MatchingEngineExecutionResult, MatchingEnginePort } from "./engine-port";

type LedgerDbClient = PrismaClient | Prisma.TransactionClient;

export class DbMatchingEngine implements MatchingEnginePort {
  readonly name = "DB_MATCHER";

  async executeLimitOrder(
    input: MatchingEngineExecutionInput,
    db: LedgerDbClient,
  ): Promise<MatchingEngineExecutionResult> {
    const execution = await executeLimitOrderAgainstBook(
      {
        orderId: input.orderId,
        quoteFeeBps: input.quoteFeeBps ?? "0",
      },
      db,
    );

    const orderReconciliation = await reconcileOrderExecution(input.orderId, db);

    return {
      execution,
      orderReconciliation,
      engine: this.name,
    };
  }
}

export const dbMatchingEngine = new DbMatchingEngine();
"""))

(submit_path := matching_dir / "submit-limit-order.ts").write_text(dedent("""
import { Prisma, TradeMode, type PrismaClient } from "@prisma/client";

import { prisma } from "../prisma";
import { reserveOrderOnPlacement } from "../ledger";
import { normalizeTimeInForce } from "../ledger/time-in-force";
import { ORDER_STATUS } from "../ledger/order-state";
import { dbMatchingEngine } from "./db-matching-engine";
import type { MatchingEnginePort } from "./engine-port";

export type SubmitLimitOrderInput = {
  userId: string;
  symbol: string;
  side: "BUY" | "SELL";
  price: string;
  qty: string;
  mode: TradeMode;
  quoteFeeBps?: string;
  timeInForce?: string;
  source: "HUMAN" | "AGENT";
};

export async function submitLimitOrder(
  input: SubmitLimitOrderInput,
  db: PrismaClient = prisma,
  engine: MatchingEnginePort = dbMatchingEngine,
) {
  const normalizedTimeInForce = normalizeTimeInForce(input.timeInForce);

  return db.$transaction(async (tx) => {
    const order = await tx.order.create({
      data: {
        symbol: input.symbol,
        side: input.side,
        price: new Prisma.Decimal(input.price),
        qty: new Prisma.Decimal(input.qty),
        status: ORDER_STATUS.OPEN,
        timeInForce: normalizedTimeInForce as any,
        mode: input.mode,
        userId: input.userId,
      },
    });

    const ledgerReservation = await reserveOrderOnPlacement(
      {
        orderId: order.id,
        userId: input.userId,
        symbol: input.symbol,
        side: input.side,
        qty: input.qty,
        price: input.price,
        mode: input.mode,
      },
      tx,
    );

    const engineResult = await engine.executeLimitOrder(
      {
        orderId: order.id,
        quoteFeeBps: input.quoteFeeBps ?? "0",
      },
      tx,
    );

    return {
      order,
      ledgerReservation,
      execution: engineResult.execution,
      orderReconciliation: engineResult.orderReconciliation,
      engine: engineResult.engine,
      source: input.source,
      timeInForce: normalizedTimeInForce,
    };
  });
}
"""))

(index_path := matching_dir / "index.ts").write_text(dedent("""
export * from "./engine-port";
export * from "./db-matching-engine";
export * from "./submit-limit-order";
"""))

# patch orders.ts
orders_text = orders_path.read_text()
if 'import { submitLimitOrder } from "../lib/matching/submit-limit-order";' not in orders_text:
    anchor = 'import { prisma } from "../lib/prisma";'
    if anchor not in orders_text:
        raise SystemExit("Could not find prisma import anchor in orders.ts")
    orders_text = orders_text.replace(
        anchor,
        anchor + '\nimport { submitLimitOrder } from "../lib/matching/submit-limit-order";',
        1,
    )

orders_pattern = re.compile(
    r'const result = await prisma\.\$transaction\(async \(tx\) => \{.*?\n\s*\}\);\n\s*return res\.json\(\{ ok: true, \.\.\.result \}\);',
    re.DOTALL,
)
orders_replacement = """const result = await submitLimitOrder(
        {
          userId,
          symbol: payload.symbol,
          side: payload.side,
          price: payload.price,
          qty: payload.qty,
          mode: payload.mode as TradeMode,
          quoteFeeBps: payload.quoteFeeBps ?? "0",
          timeInForce: normalizedTimeInForce,
          source: "HUMAN",
        },
        prisma,
      );

      return res.json({ ok: true, ...result });"""
orders_text, count = orders_pattern.subn(orders_replacement, orders_text, count=1)
if count == 0 and 'source: "HUMAN"' not in orders_text:
    raise SystemExit("Could not patch human placement flow in orders.ts")
orders_path.write_text(orders_text)

# patch trade.ts
trade_text = trade_path.read_text()
if 'import { submitLimitOrder } from "../lib/matching/submit-limit-order";' not in trade_text:
    anchor = 'import { prisma } from "../lib/prisma";'
    if anchor not in trade_text:
        raise SystemExit("Could not find prisma import anchor in trade.ts")
    trade_text = trade_text.replace(
        anchor,
        anchor + '\nimport { submitLimitOrder } from "../lib/matching/submit-limit-order";',
        1,
    )

trade_pattern = re.compile(
    r'const result = await prisma\.\$transaction\(async \(tx\) => \{.*?\n\s*\}\);\n\n\s*await bumpOrdersPlaced\(principal\.mandateId \?\? principal\.mandate\?\.id\);\n\n\s*return res\.json\(\{ ok: true, \.\.\.result \}\);',
    re.DOTALL,
)
trade_replacement = """const result = await submitLimitOrder(
        {
          userId: principal.userId,
          symbol: payload.symbol,
          side: payload.side,
          price: payload.price!,
          qty: payload.qty,
          mode: payload.mode as TradeMode,
          quoteFeeBps: payload.quoteFeeBps ?? "0",
          timeInForce: payload.tif ?? "GTC",
          source: "AGENT",
        },
        prisma,
      );

      await bumpOrdersPlaced(principal.mandateId ?? principal.mandate?.id);

      return res.json({ ok: true, ...result });"""
trade_text, count = trade_pattern.subn(trade_replacement, trade_text, count=1)
if count == 0 and 'source: "AGENT"' not in trade_text:
    raise SystemExit("Could not patch agent placement flow in trade.ts")
trade_path.write_text(trade_text)

(test_path := root / "apps/api/test/order-submission-unification.test.ts").write_text(dedent("""
import { beforeEach, describe, expect, it, vi } from "vitest";

const { reserveOrderOnPlacement, executeLimitOrderAgainstBook, reconcileOrderExecution } = vi.hoisted(() => ({
  reserveOrderOnPlacement: vi.fn(),
  executeLimitOrderAgainstBook: vi.fn(),
  reconcileOrderExecution: vi.fn(),
}));

vi.mock("../src/lib/ledger", () => ({
  reserveOrderOnPlacement,
  executeLimitOrderAgainstBook,
  reconcileOrderExecution,
}));

import { DbMatchingEngine } from "../src/lib/matching/db-matching-engine";
import { submitLimitOrder } from "../src/lib/matching/submit-limit-order";

describe("order submission unification", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("db matching engine delegates to execution and reconciliation helpers", async () => {
    executeLimitOrderAgainstBook.mockResolvedValue({ order: { id: 10n }, fills: [], remainingQty: "0" });
    reconcileOrderExecution.mockResolvedValue({ orderId: "10", ok: true });

    const engine = new DbMatchingEngine();
    const result = await engine.executeLimitOrder({ orderId: 10n, quoteFeeBps: "5" }, {} as any);

    expect(executeLimitOrderAgainstBook).toHaveBeenCalledWith(
      { orderId: 10n, quoteFeeBps: "5" },
      {} as any,
    );
    expect(reconcileOrderExecution).toHaveBeenCalledWith(10n, {} as any);
    expect(result.engine).toBe("DB_MATCHER");
  });

  it("submitLimitOrder creates, reserves, and dispatches through the shared engine boundary", async () => {
    const tx = {
      order: {
        create: vi.fn().mockResolvedValue({
          id: 101n,
          symbol: "BTC-USD",
          side: "BUY",
          price: "100",
          qty: "1",
          status: "OPEN",
          timeInForce: "IOC",
          mode: "PAPER",
          userId: "user-1",
        }),
      },
    };

    const fakeDb = {
      $transaction: vi.fn(async (fn: any) => fn(tx)),
    };

    reserveOrderOnPlacement.mockResolvedValue({ id: "reserve-1" });

    const engine = {
      name: "DB_MATCHER",
      executeLimitOrder: vi.fn().mockResolvedValue({
        execution: { order: { id: 101n }, fills: [], remainingQty: "0" },
        orderReconciliation: { orderId: "101", ok: true },
        engine: "DB_MATCHER",
      }),
    };

    const result = await submitLimitOrder(
      {
        userId: "user-1",
        symbol: "BTC-USD",
        side: "BUY",
        price: "100",
        qty: "1",
        mode: "PAPER" as any,
        quoteFeeBps: "5",
        timeInForce: "IOC",
        source: "HUMAN",
      },
      fakeDb as any,
      engine as any,
    );

    expect(fakeDb.$transaction).toHaveBeenCalledTimes(1);
    expect(tx.order.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        symbol: "BTC-USD",
        side: "BUY",
        userId: "user-1",
        status: "OPEN",
        timeInForce: "IOC",
      }),
    });
    expect(reserveOrderOnPlacement).toHaveBeenCalledWith(
      expect.objectContaining({
        orderId: 101n,
        userId: "user-1",
        symbol: "BTC-USD",
      }),
      tx,
    );
    expect(engine.executeLimitOrder).toHaveBeenCalledWith(
      { orderId: 101n, quoteFeeBps: "5" },
      tx,
    );
    expect(result.engine).toBe("DB_MATCHER");
    expect(result.source).toBe("HUMAN");
    expect(result.timeInForce).toBe("IOC");
  });
});
"""))

print("Patched package.json, added matching engine port + db adapter + submitLimitOrder service, patched orders.ts and trade.ts to use the shared submission boundary, and wrote apps/api/test/order-submission-unification.test.ts for Phase 4A.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 4A patch applied."
