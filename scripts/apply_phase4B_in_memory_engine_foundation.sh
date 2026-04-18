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
submit_path = root / "apps/api/src/lib/matching/submit-limit-order.ts"
index_path = root / "apps/api/src/lib/matching/index.ts"

for p in [pkg_path, submit_path, index_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:matching:in-memory"] = "vitest run test/in-memory-matching-engine.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

matching_dir = root / "apps/api/src/lib/matching"
book_path = matching_dir / "in-memory-order-book.ts"
engine_path = matching_dir / "in-memory-matching-engine.ts"
selector_path = matching_dir / "select-engine.ts"
test_path = root / "apps/api/test/in-memory-matching-engine.test.ts"

book_path.write_text(dedent("""\
import { Decimal } from "@prisma/client/runtime/library";
import { type OrderSide } from "@prisma/client";

import { sortMakersForTaker } from "../ledger/matching-priority";
import { deriveTifRestingAction, normalizeTimeInForce } from "../ledger/time-in-force";

type Decimalish = string | number | Decimal;

function toDecimal(value: Decimalish): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

function minDecimal(a: Decimal, b: Decimal): Decimal {
  return a.lessThanOrEqualTo(b) ? a : b;
}

export type InMemoryBookOrder = {
  orderId: string;
  symbol: string;
  side: OrderSide;
  price: Decimal;
  remainingQty: Decimal;
  createdAt: Date;
  timeInForce: string;
};

export type InMemoryFill = {
  makerOrderId: string;
  takerOrderId: string;
  qty: string;
  price: string;
};

export class InMemoryOrderBook {
  private readonly bids: InMemoryBookOrder[] = [];
  private readonly asks: InMemoryBookOrder[] = [];

  add(order: Omit<InMemoryBookOrder, "price" | "remainingQty" | "createdAt"> & {
    price: Decimalish;
    remainingQty: Decimalish;
    createdAt?: Date | string | number;
  }): InMemoryBookOrder {
    const normalized: InMemoryBookOrder = {
      ...order,
      price: toDecimal(order.price),
      remainingQty: toDecimal(order.remainingQty),
      createdAt: order.createdAt instanceof Date ? order.createdAt : new Date(order.createdAt ?? Date.now()),
    };
    const side = normalized.side === "BUY" ? this.bids : this.asks;
    side.push(normalized);
    return normalized;
  }

  remove(orderId: string): boolean {
    const before = this.bids.length + this.asks.length;
    const nextBids = this.bids.filter((o) => o.orderId !== orderId);
    const nextAsks = this.asks.filter((o) => o.orderId !== orderId);
    this.bids.splice(0, this.bids.length, ...nextBids);
    this.asks.splice(0, this.asks.length, ...nextAsks);
    return before !== this.bids.length + this.asks.length;
  }

  snapshot(side: OrderSide): InMemoryBookOrder[] {
    const source = side === "BUY" ? this.bids : this.asks;
    return source.map((o) => ({ ...o }));
  }

  matchIncoming(input: {
    orderId: string;
    symbol: string;
    side: OrderSide;
    price: Decimalish;
    qty: Decimalish;
    timeInForce?: string;
    createdAt?: Date | string | number;
  }): {
    fills: InMemoryFill[];
    remainingQty: string;
    tifAction: "KEEP_OPEN" | "CANCEL_REMAINDER" | "FILLED";
    restingOrderId: string | null;
  } {
    const tif = normalizeTimeInForce(input.timeInForce);
    const takerPrice = toDecimal(input.price);
    let remaining = toDecimal(input.qty);

    const opposite = input.side === "BUY" ? this.asks : this.bids;
    const sortedOpposite = sortMakersForTaker(input.side, opposite);

    const fills: InMemoryFill[] = [];

    for (const maker of sortedOpposite) {
      if (remaining.lessThanOrEqualTo(0)) break;

      const crosses =
        input.side === "BUY"
          ? maker.price.lessThanOrEqualTo(takerPrice)
          : maker.price.greaterThanOrEqualTo(takerPrice);

      if (!crosses) break;
      if (maker.remainingQty.lessThanOrEqualTo(0)) continue;

      const fillQty = minDecimal(remaining, maker.remainingQty);
      maker.remainingQty = maker.remainingQty.minus(fillQty);
      remaining = remaining.minus(fillQty);

      fills.push({
        makerOrderId: maker.orderId,
        takerOrderId: input.orderId,
        qty: fillQty.toString(),
        price: maker.price.toString(),
      });

      if (maker.remainingQty.lessThanOrEqualTo(0)) {
        this.remove(maker.orderId);
      } else {
        const bookSide = maker.side === "BUY" ? this.bids : this.asks;
        const idx = bookSide.findIndex((o) => o.orderId === maker.orderId);
        if (idx >= 0) bookSide[idx] = maker;
      }
    }

    const executedQty = toDecimal(input.qty).minus(remaining);
    const tifAction = deriveTifRestingAction(tif, executedQty, input.qty);

    let restingOrderId: string | null = null;
    if (tifAction === "KEEP_OPEN" && remaining.greaterThan(0)) {
      const resting = this.add({
        orderId: input.orderId,
        symbol: input.symbol,
        side: input.side,
        price: takerPrice,
        remainingQty: remaining,
        createdAt: input.createdAt,
        timeInForce: tif,
      });
      restingOrderId = resting.orderId;
    }

    return {
      fills,
      remainingQty: remaining.toString(),
      tifAction,
      restingOrderId,
    };
  }
}
"""))

engine_path.write_text(dedent("""\
import { Decimal } from "@prisma/client/runtime/library";
import { type PrismaClient, type Prisma } from "@prisma/client";

import { getOrderRemainingQty } from "../ledger/execution";
import type {
  MatchingEngineExecutionInput,
  MatchingEngineExecutionResult,
  MatchingEnginePort,
} from "./engine-port";
import { InMemoryOrderBook } from "./in-memory-order-book";

type LedgerDbClient = PrismaClient | Prisma.TransactionClient;

export class InMemoryMatchingEngine implements MatchingEnginePort {
  readonly name = "IN_MEMORY_MATCHER";
  private readonly books = new Map<string, InMemoryOrderBook>();

  private getBookKey(symbol: string, mode: string): string {
    return `${symbol}:${mode}`;
  }

  private getBook(symbol: string, mode: string): InMemoryOrderBook {
    const key = this.getBookKey(symbol, mode);
    let existing = this.books.get(key);
    if (!existing) {
      existing = new InMemoryOrderBook();
      this.books.set(key, existing);
    }
    return existing;
  }

  async executeLimitOrder(
    input: MatchingEngineExecutionInput,
    db: LedgerDbClient,
  ): Promise<MatchingEngineExecutionResult> {
    const order = await db.order.findUniqueOrThrow({
      where: { id: BigInt(String(input.orderId)) },
    });

    const remainingQty = await getOrderRemainingQty(order as any, db as any);
    const book = this.getBook(order.symbol, order.mode);

    const execution = book.matchIncoming({
      orderId: order.id.toString(),
      symbol: order.symbol,
      side: order.side as any,
      price: new Decimal(order.price),
      qty: remainingQty,
      timeInForce: (order as any).timeInForce ?? "GTC",
      createdAt: order.createdAt,
    });

    return {
      execution: {
        order: {
          id: order.id,
          symbol: order.symbol,
          side: order.side,
          price: order.price,
          qty: order.qty,
          status: order.status,
          mode: order.mode,
          createdAt: order.createdAt,
          timeInForce: (order as any).timeInForce ?? "GTC",
        },
        fills: execution.fills,
        remainingQty: execution.remainingQty,
        tifAction: execution.tifAction,
        restingOrderId: execution.restingOrderId,
      },
      orderReconciliation: {
        ok: true,
        engine: this.name,
        note: "Experimental in-memory engine foundation; ledger settlement is not yet integrated.",
      },
      engine: this.name,
    };
  }
}

export const inMemoryMatchingEngine = new InMemoryMatchingEngine();
"""))

selector_path.write_text(dedent("""\
import { dbMatchingEngine } from "./db-matching-engine";
import { inMemoryMatchingEngine } from "./in-memory-matching-engine";
import type { MatchingEnginePort } from "./engine-port";

export type MatchingEngineSelection = "db" | "in_memory" | "DB_MATCHER" | "IN_MEMORY_MATCHER";

export function selectMatchingEngine(
  preferred?: MatchingEngineSelection | null,
): MatchingEnginePort {
  const selected = String(preferred ?? process.env.MATCHING_ENGINE ?? "db").trim();

  if (selected === "in_memory" || selected === "IN_MEMORY_MATCHER") {
    return inMemoryMatchingEngine;
  }

  return dbMatchingEngine;
}
"""))

submit_text = submit_path.read_text()
if 'import { selectMatchingEngine } from "./select-engine";' not in submit_text:
    submit_text = submit_text.replace(
        'import { dbMatchingEngine } from "./db-matching-engine";\n',
        'import { dbMatchingEngine } from "./db-matching-engine";\nimport { selectMatchingEngine } from "./select-engine";\n',
        1,
    )
submit_text = submit_text.replace(
    '  engine: MatchingEnginePort = dbMatchingEngine,\n) {\n  const normalizedTimeInForce = normalizeTimeInForce(input.timeInForce);\n',
    '  engine?: MatchingEnginePort,\n) {\n  const normalizedTimeInForce = normalizeTimeInForce(input.timeInForce);\n  const selectedEngine = engine ?? selectMatchingEngine();\n',
    1,
)
submit_text = submit_text.replace(
    '    const engineResult = await engine.executeLimitOrder(\n',
    '    const engineResult = await selectedEngine.executeLimitOrder(\n',
    1,
)
submit_path.write_text(submit_text)

index_text = index_path.read_text()
for export_line in [
    'export * from "./in-memory-order-book";',
    'export * from "./in-memory-matching-engine";',
    'export * from "./select-engine";',
]:
    if export_line not in index_text:
        index_text = index_text.rstrip() + "\n" + export_line + "\n"
index_path.write_text(index_text)

test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(dedent("""\
import { beforeEach, describe, expect, it, vi } from "vitest";
import { Decimal } from "@prisma/client/runtime/library";

const { prismaMock } = vi.hoisted(() => ({
  prismaMock: {
    order: {
      findUniqueOrThrow: vi.fn(),
    },
    trade: {
      aggregate: vi.fn(),
    },
  },
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));

import { InMemoryOrderBook } from "../src/lib/matching/in-memory-order-book";
import { InMemoryMatchingEngine } from "../src/lib/matching/in-memory-matching-engine";
import { dbMatchingEngine } from "../src/lib/matching/db-matching-engine";
import { selectMatchingEngine } from "../src/lib/matching/select-engine";

describe("in-memory matching engine foundation", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    delete process.env.MATCHING_ENGINE;
  });

  it("matches BUY takers against the best asks using price-time priority", () => {
    const book = new InMemoryOrderBook();
    book.add({
      orderId: "ask-2",
      symbol: "BTC-USD",
      side: "SELL",
      price: "99",
      remainingQty: "2",
      createdAt: new Date("2026-01-01T00:10:00Z"),
      timeInForce: "GTC",
    });
    book.add({
      orderId: "ask-1",
      symbol: "BTC-USD",
      side: "SELL",
      price: "99",
      remainingQty: "3",
      createdAt: new Date("2026-01-01T00:00:00Z"),
      timeInForce: "GTC",
    });
    book.add({
      orderId: "ask-3",
      symbol: "BTC-USD",
      side: "SELL",
      price: "100",
      remainingQty: "5",
      createdAt: new Date("2026-01-01T00:00:00Z"),
      timeInForce: "GTC",
    });

    const result = book.matchIncoming({
      orderId: "buy-1",
      symbol: "BTC-USD",
      side: "BUY",
      price: "100",
      qty: "6",
      timeInForce: "GTC",
      createdAt: new Date("2026-01-01T01:00:00Z"),
    });

    expect(result.fills.map((f) => f.makerOrderId)).toEqual(["ask-1", "ask-2", "ask-3"]);
    expect(result.fills.map((f) => f.qty)).toEqual(["3", "2", "1"]);
    expect(result.remainingQty).toBe("0");
    expect(result.tifAction).toBe("FILLED");
  });

  it("rests remaining GTC quantity on the book but cancels IOC remainder", () => {
    const gtcBook = new InMemoryOrderBook();
    const gtcResult = gtcBook.matchIncoming({
      orderId: "buy-gtc",
      symbol: "BTC-USD",
      side: "BUY",
      price: "100",
      qty: "5",
      timeInForce: "GTC",
      createdAt: new Date("2026-01-01T01:00:00Z"),
    });

    expect(gtcResult.remainingQty).toBe("5");
    expect(gtcResult.tifAction).toBe("KEEP_OPEN");
    expect(gtcBook.snapshot("BUY")).toHaveLength(1);

    const iocBook = new InMemoryOrderBook();
    const iocResult = iocBook.matchIncoming({
      orderId: "buy-ioc",
      symbol: "BTC-USD",
      side: "BUY",
      price: "100",
      qty: "5",
      timeInForce: "IOC",
      createdAt: new Date("2026-01-01T01:00:00Z"),
    });

    expect(iocResult.remainingQty).toBe("5");
    expect(iocResult.tifAction).toBe("CANCEL_REMAINDER");
    expect(iocBook.snapshot("BUY")).toHaveLength(0);
  });

  it("selectMatchingEngine defaults to DB and can explicitly choose in-memory", () => {
    expect(selectMatchingEngine()).toBe(dbMatchingEngine);
    expect(selectMatchingEngine("in_memory").name).toBe("IN_MEMORY_MATCHER");

    process.env.MATCHING_ENGINE = "IN_MEMORY_MATCHER";
    expect(selectMatchingEngine().name).toBe("IN_MEMORY_MATCHER");
  });

  it("in-memory engine stages and matches orders across successive submissions", async () => {
    const sellOrder = {
      id: 1n,
      symbol: "BTC-USD",
      side: "SELL",
      price: new Decimal("99"),
      qty: new Decimal("3"),
      status: "OPEN",
      mode: "PAPER",
      createdAt: new Date("2026-01-01T00:00:00Z"),
      timeInForce: "GTC",
    };
    const buyOrder = {
      id: 2n,
      symbol: "BTC-USD",
      side: "BUY",
      price: new Decimal("100"),
      qty: new Decimal("2"),
      status: "OPEN",
      mode: "PAPER",
      createdAt: new Date("2026-01-01T00:01:00Z"),
      timeInForce: "IOC",
    };

    prismaMock.order.findUniqueOrThrow
      .mockResolvedValueOnce(sellOrder)
      .mockResolvedValueOnce(buyOrder);

    prismaMock.trade.aggregate
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } })
      .mockResolvedValueOnce({ _sum: { qty: new Decimal("0") } });

    const engine = new InMemoryMatchingEngine();

    const first = await engine.executeLimitOrder({ orderId: sellOrder.id }, prismaMock as any);
    const second = await engine.executeLimitOrder({ orderId: buyOrder.id }, prismaMock as any);

    expect(first.engine).toBe("IN_MEMORY_MATCHER");
    expect((first.execution as any).restingOrderId).toBe("1");
    expect((second.execution as any).fills).toHaveLength(1);
    expect((second.execution as any).fills[0]).toEqual(
      expect.objectContaining({ makerOrderId: "1", qty: "2", price: "99" }),
    );
  });
});
"""))

print("Patched package.json, added in-memory order-book and engine foundation behind MatchingEnginePort, updated submit-limit-order.ts to use the engine selector seam, and wrote apps/api/test/in-memory-matching-engine.test.ts for Phase 4B.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 4B patch applied."
