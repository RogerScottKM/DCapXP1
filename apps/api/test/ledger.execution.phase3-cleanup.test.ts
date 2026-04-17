import { beforeEach, describe, expect, it, vi } from "vitest";
import { Decimal } from "@prisma/client/runtime/library";

const {
  prismaMock,
  ensureUserLedgerAccounts,
  postLedgerTransaction,
  settleMatchedTrade,
  releaseOrderOnCancel,
  reconcileTradeSettlement,
} = vi.hoisted(() => ({
  prismaMock: {
    order: {
      findUniqueOrThrow: vi.fn(),
      findUnique: vi.fn(),
      findMany: vi.fn(),
      update: vi.fn(),
    },
    trade: {
      aggregate: vi.fn(),
      create: vi.fn(),
      findMany: vi.fn(),
    },
    ledgerTransaction: {
      findFirst: vi.fn(),
      findMany: vi.fn(),
    },
  },
  ensureUserLedgerAccounts: vi.fn(),
  postLedgerTransaction: vi.fn(),
  settleMatchedTrade: vi.fn(),
  releaseOrderOnCancel: vi.fn(),
  reconcileTradeSettlement: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/ledger/accounts", () => ({ ensureUserLedgerAccounts }));
vi.mock("../src/lib/ledger/service", () => ({ postLedgerTransaction }));
vi.mock("../src/lib/ledger/order-lifecycle", () => ({
  settleMatchedTrade,
  releaseOrderOnCancel,
}));
vi.mock("../src/lib/ledger/reconciliation", async () => {
  const actual = await vi.importActual("../src/lib/ledger/reconciliation");
  return {
    ...actual,
    reconcileTradeSettlement,
  };
});

import {
  executeLimitOrderAgainstBook,
  syncOrderStatusFromTrades,
} from "../src/lib/ledger/execution";
import { ORDER_STATUS } from "../src/lib/ledger/order-state";

function mkOrder(overrides: any = {}) {
  return {
    id: 1n,
    userId: "user-1",
    symbol: "BTC-USD",
    side: "BUY",
    price: new Decimal("100"),
    qty: new Decimal("10"),
    status: ORDER_STATUS.OPEN,
    mode: "PAPER",
    timeInForce: "GTC",
    createdAt: new Date("2026-01-01T00:00:00Z"),
    ...overrides,
  };
}

function agg(qty: string | number | Decimal | null) {
  return { _sum: { qty: qty === null ? null : new Decimal(qty) } };
}

beforeEach(() => {
  vi.clearAllMocks();
  ensureUserLedgerAccounts.mockResolvedValue({
    available: { id: "acct-available", assetCode: "USD" },
    held: { id: "acct-held", assetCode: "USD" },
  });
  postLedgerTransaction.mockResolvedValue({ id: "ltx-1" });
  settleMatchedTrade.mockResolvedValue({ id: "ltx-settle" });
  releaseOrderOnCancel.mockResolvedValue({ id: "ltx-release" });
  reconcileTradeSettlement.mockResolvedValue({ ok: true });
  prismaMock.ledgerTransaction.findFirst.mockResolvedValue(null);
  prismaMock.ledgerTransaction.findMany.mockResolvedValue([]);
  prismaMock.trade.findMany.mockResolvedValue([]);
});

describe("phase 3 execution cleanup", () => {
  it("allows a PARTIALLY_FILLED taker to re-enter matching", async () => {
    const taker = mkOrder({ id: 100n, status: ORDER_STATUS.PARTIALLY_FILLED, qty: new Decimal("10") });

    prismaMock.order.findUniqueOrThrow
      .mockResolvedValueOnce(taker)
      .mockResolvedValueOnce(taker);
    prismaMock.order.findMany.mockResolvedValue([]);
    prismaMock.trade.aggregate
      .mockResolvedValueOnce(agg("4"))
      .mockResolvedValueOnce(agg("0"))
      .mockResolvedValueOnce(agg("4"))
      .mockResolvedValueOnce(agg("0"))
      .mockResolvedValueOnce(agg("4"))
      .mockResolvedValueOnce(agg("0"));

    const result = await executeLimitOrderAgainstBook({ orderId: taker.id });

    expect(result.fills).toHaveLength(0);
    expect(result.remainingQty).toBe("6");
  });

  it("skips a maker that turned CANCELLED after initial candidate selection", async () => {
    const taker = mkOrder({ id: 100n, status: ORDER_STATUS.OPEN, qty: new Decimal("10") });
    const staleMaker = mkOrder({
      id: 200n,
      userId: "user-2",
      side: "SELL",
      qty: new Decimal("4"),
      price: new Decimal("95"),
      status: ORDER_STATUS.OPEN,
    });

    prismaMock.order.findUniqueOrThrow
      .mockResolvedValueOnce(taker)
      .mockResolvedValueOnce(taker);
    prismaMock.order.findMany.mockResolvedValue([staleMaker]);
    prismaMock.order.findUnique.mockResolvedValueOnce({
      ...staleMaker,
      status: ORDER_STATUS.CANCELLED,
    });
    prismaMock.trade.aggregate
      .mockResolvedValueOnce(agg("0"))
      .mockResolvedValueOnce(agg("0"))
      .mockResolvedValueOnce(agg("0"))
      .mockResolvedValueOnce(agg("0"))
      .mockResolvedValueOnce(agg("0"))
      .mockResolvedValueOnce(agg("0"));

    const result = await executeLimitOrderAgainstBook({ orderId: taker.id });

    expect(result.fills).toHaveLength(0);
    expect(prismaMock.trade.create).not.toHaveBeenCalled();
  });

  it("cancels IOC remainder through releaseOrderOnCancel and marks the order CANCELLED", async () => {
    const taker = mkOrder({
      id: 100n,
      status: ORDER_STATUS.OPEN,
      qty: new Decimal("10"),
      timeInForce: "IOC",
    });
    const maker = mkOrder({
      id: 200n,
      userId: "user-2",
      side: "SELL",
      qty: new Decimal("4"),
      price: new Decimal("95"),
      status: ORDER_STATUS.OPEN,
    });

    prismaMock.order.findUniqueOrThrow.mockImplementation(async ({ where }: any) => {
      const id = BigInt(String(where.id));
      if (id == taker.id) {
        return taker;
      }
      if (id == maker.id) {
        return maker;
      }
      return taker;
    });

    prismaMock.order.findMany.mockResolvedValue([maker]);
    prismaMock.order.findUnique
      .mockResolvedValueOnce(maker)
      .mockResolvedValueOnce({ ...maker, status: ORDER_STATUS.FILLED });

    prismaMock.trade.aggregate
      .mockResolvedValueOnce(agg("0"))
      .mockResolvedValueOnce(agg("0"))
      .mockResolvedValueOnce(agg("0"))
      .mockResolvedValueOnce(agg("0"))
      .mockResolvedValueOnce(agg("4"))
      .mockResolvedValueOnce(agg("0"))
      .mockResolvedValueOnce(agg("0"))
      .mockResolvedValueOnce(agg("4"))
      .mockResolvedValueOnce(agg("4"))
      .mockResolvedValueOnce(agg("0"))
      .mockResolvedValueOnce(agg("4"))
      .mockResolvedValueOnce(agg("0"));

    prismaMock.trade.create.mockResolvedValue({
      id: 500n,
      symbol: "BTC-USD",
      qty: new Decimal("4"),
      price: new Decimal("95"),
      buyOrderId: taker.id,
      sellOrderId: maker.id,
      mode: "PAPER",
    });

    prismaMock.order.update.mockImplementation(async ({ where, data }: any) => {
      const id = BigInt(String(where.id));
      if (id == taker.id) return { ...taker, ...data };
      if (id == maker.id) return { ...maker, ...data };
      return { ...taker, ...data };
    });

    const result = await executeLimitOrderAgainstBook({ orderId: taker.id });

    expect(releaseOrderOnCancel).toHaveBeenCalledTimes(1);
    expect(prismaMock.order.update).toHaveBeenCalledWith({
      where: { id: taker.id },
      data: { status: ORDER_STATUS.CANCELLED },
    });
    expect(result.tifAction).toBe("CANCEL_REMAINDER");
  });

  it("syncOrderStatusFromTrades preserves FILLED as a terminal state", async () => {
    const order = mkOrder({ qty: new Decimal("10"), status: ORDER_STATUS.FILLED });
    prismaMock.order.findUniqueOrThrow.mockResolvedValue(order);
    prismaMock.trade.aggregate
      .mockResolvedValueOnce(agg("10"))
      .mockResolvedValueOnce(agg("0"));
    prismaMock.order.update.mockImplementation(async ({ data }: any) => ({ ...order, ...data }));

    const result = await syncOrderStatusFromTrades(order.id);

    expect(result.status).toBe(ORDER_STATUS.FILLED);
  });
});
