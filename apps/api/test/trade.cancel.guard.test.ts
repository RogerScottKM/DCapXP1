import { Decimal } from "@prisma/client/runtime/library";
import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  prismaMock,
  getOrderRemainingQty,
  releaseOrderOnCancel,
  reserveOrderOnPlacement,
  executeLimitOrderAgainstBook,
  reconcileOrderExecution,
  syncOrderStatusFromTrades,
  reconcileTradeSettlement,
  settleMatchedTrade,
  enforceMandate,
  bumpOrdersPlaced,
} = vi.hoisted(() => ({
  prismaMock: {
    order: { findUnique: vi.fn() },
    $transaction: vi.fn(),
  },
  getOrderRemainingQty: vi.fn(),
  releaseOrderOnCancel: vi.fn(),
  reserveOrderOnPlacement: vi.fn(),
  executeLimitOrderAgainstBook: vi.fn(),
  reconcileOrderExecution: vi.fn(),
  syncOrderStatusFromTrades: vi.fn(),
  reconcileTradeSettlement: vi.fn(),
  settleMatchedTrade: vi.fn(),
  enforceMandate: vi.fn(() => (_req: any, _res: any, next: (err?: unknown) => void) => next()),
  bumpOrdersPlaced: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/ledger", () => ({
  getOrderRemainingQty,
  releaseOrderOnCancel,
  reserveOrderOnPlacement,
  executeLimitOrderAgainstBook,
  reconcileOrderExecution,
  syncOrderStatusFromTrades,
  reconcileTradeSettlement,
  settleMatchedTrade,
}));
vi.mock("../src/middleware/ibac", () => ({
  enforceMandate,
  bumpOrdersPlaced,
}));

import router from "../src/routes/trade";

function createRes() {
  const res: any = {};
  res.status = vi.fn(() => res);
  res.json = vi.fn(() => res);
  return res;
}

function getCancelHandler() {
  const layer = (router as any).stack.find(
    (entry: any) => entry.route?.path === "/orders/:orderId/cancel",
  );
  if (!layer) {
    throw new Error("Cancel route not found");
  }
  return layer.route.stack[layer.route.stack.length - 1].handle;
}

describe("trade route cancel guard", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("allows cancelling a PARTIALLY_FILLED order with remaining quantity", async () => {
    const handler = getCancelHandler();
    const order = {
      id: 101n,
      userId: "user-1",
      status: "PARTIALLY_FILLED",
      symbol: "BTC-USD",
      side: "BUY",
      price: new Decimal("100"),
      mode: "PAPER",
    };

    prismaMock.order.findUnique.mockResolvedValue(order);
    getOrderRemainingQty.mockResolvedValue(new Decimal("6"));
    releaseOrderOnCancel.mockResolvedValue({ ok: true });

    prismaMock.$transaction.mockImplementation(async (fn: any) =>
      fn({
        order: {
          update: vi.fn().mockResolvedValue({
            ...order,
            status: "CANCELLED",
          }),
        },
      }),
    );

    const req: any = {
      params: { orderId: "101" },
      principal: { type: "AGENT", userId: "user-1" },
    };
    const res = createRes();

    await handler(req, res);

    expect(res.status).not.toHaveBeenCalledWith(409);
    expect(releaseOrderOnCancel).toHaveBeenCalled();
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        ok: true,
        remainingQty: "6",
      }),
    );
  });

  it("rejects cancelling a FILLED order", async () => {
    const handler = getCancelHandler();

    prismaMock.order.findUnique.mockResolvedValue({
      id: 102n,
      userId: "user-1",
      status: "FILLED",
      symbol: "BTC-USD",
      side: "BUY",
      price: new Decimal("100"),
      mode: "PAPER",
    });
    getOrderRemainingQty.mockResolvedValue(new Decimal("0"));

    const req: any = {
      params: { orderId: "102" },
      principal: { type: "AGENT", userId: "user-1" },
    };
    const res = createRes();

    await handler(req, res);

    expect(res.status).toHaveBeenCalledWith(409);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        error: expect.stringContaining("Cannot cancel order in status FILLED"),
      }),
    );
  });

  it("rejects cancelling a CANCEL_PENDING order", async () => {
    const handler = getCancelHandler();

    prismaMock.order.findUnique.mockResolvedValue({
      id: 103n,
      userId: "user-1",
      status: "CANCEL_PENDING",
      symbol: "BTC-USD",
      side: "BUY",
      price: new Decimal("100"),
      mode: "PAPER",
    });
    getOrderRemainingQty.mockResolvedValue(new Decimal("5"));

    const req: any = {
      params: { orderId: "103" },
      principal: { type: "AGENT", userId: "user-1" },
    };
    const res = createRes();

    await handler(req, res);

    expect(res.status).toHaveBeenCalledWith(409);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        error: expect.stringContaining("Cannot cancel order in status CANCEL_PENDING"),
      }),
    );
  });

  it("rejects cancelling an order with no remaining quantity", async () => {
    const handler = getCancelHandler();

    prismaMock.order.findUnique.mockResolvedValue({
      id: 104n,
      userId: "user-1",
      status: "PARTIALLY_FILLED",
      symbol: "BTC-USD",
      side: "BUY",
      price: new Decimal("100"),
      mode: "PAPER",
    });
    getOrderRemainingQty.mockResolvedValue(new Decimal("0"));

    const req: any = {
      params: { orderId: "104" },
      principal: { type: "AGENT", userId: "user-1" },
    };
    const res = createRes();

    await handler(req, res);

    expect(res.status).toHaveBeenCalledWith(409);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        error: "Order has no remaining quantity to cancel.",
      }),
    );
  });
});
