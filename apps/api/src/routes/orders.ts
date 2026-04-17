import { Router } from "express";

import { Prisma, TradeMode } from "@prisma/client";
import { Decimal } from "@prisma/client/runtime/library";
import { z } from "zod";

import { prisma } from "../lib/prisma";
import { submitLimitOrder } from "../lib/matching/submit-limit-order";
import {
  executeLimitOrderAgainstBook,
  getOrderRemainingQty,
  reconcileOrderExecution,
  releaseOrderOnCancel,
  reserveOrderOnPlacement,
} from "../lib/ledger";
import { canCancel, ORDER_STATUS } from "../lib/ledger/order-state";
import { normalizeTimeInForce } from "../lib/ledger/time-in-force";
import { withIdempotency } from "../lib/idempotency";
import { requireAuth, requireRecentMfa, requireLiveModeEligible } from "../middleware/require-auth";
import { auditPrivilegedRequest } from "../middleware/audit-privileged";
import { simpleRateLimit } from "../middleware/simple-rate-limit";

const router = Router();

const orderLimiter = simpleRateLimit({
  keyPrefix: "orders:place",
  windowMs: 60 * 1000,
  max: 30,
});

const cancelLimiter = simpleRateLimit({
  keyPrefix: "orders:cancel",
  windowMs: 60 * 1000,
  max: 60,
});

const placeOrderSchema = z.object({
  symbol: z.string().min(3).max(40),
  side: z.enum(["BUY", "SELL"]),
  type: z.enum(["LIMIT"]),
  price: z.string().refine(
    (v) => { try { return new Decimal(v).greaterThan(0); } catch { return false; } },
    { message: "Price must be a positive number." },
  ),
  qty: z.string().refine(
    (v) => { try { return new Decimal(v).greaterThan(0); } catch { return false; } },
    { message: "Quantity must be a positive number." },
  ),
  mode: z.enum(["PAPER", "LIVE"]).optional().default("PAPER"),
  quoteFeeBps: z.string().optional().default("0"),
  timeInForce: z.enum(["GTC", "IOC", "FOK", "POST_ONLY"]).optional().default("GTC"),
});

router.use(requireAuth);

router.get("/", async (req, res) => {
  try {
    const userId = req.auth!.userId;
    const symbol = typeof req.query.symbol === "string"
      ? req.query.symbol.toUpperCase().trim()
      : undefined;
    const status = typeof req.query.status === "string"
      ? req.query.status.toUpperCase().trim()
      : undefined;
    const mode = typeof req.query.mode === "string"
      ? req.query.mode.toUpperCase().trim()
      : undefined;
    const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 200);

    const where: Prisma.OrderWhereInput = { userId };
    if (symbol) where.symbol = symbol;
    if (status) where.status = status as any;
    if (mode === "PAPER" || mode === "LIVE") where.mode = mode as TradeMode;

    const orders = await prisma.order.findMany({
      where,
      orderBy: { createdAt: "desc" },
      take: limit,
    });

    return res.json({
      ok: true,
      orders: orders.map((o) => ({
        id: o.id.toString(),
        symbol: o.symbol,
        side: o.side,
        price: o.price.toString(),
        qty: o.qty.toString(),
        status: o.status,
        mode: o.mode,
        timeInForce: o.timeInForce,
        createdAt: o.createdAt.toISOString(),
      })),
    });
  } catch (error: any) {
    return res.status(500).json({ error: error?.message ?? "Unable to fetch orders" });
  }
});

router.post(
  "/",
  requireRecentMfa(),
  requireLiveModeEligible(),
  orderLimiter,
  auditPrivilegedRequest("ORDER_PLACE_REQUESTED", "ORDER"),
  withIdempotency("HUMAN_ORDER_PLACE", async (req, res) => {
    try {
      const userId = req.auth!.userId;
      const payload = placeOrderSchema.parse(req.body);
      const normalizedTimeInForce = normalizeTimeInForce(payload.timeInForce);

      const market = await prisma.market.findUnique({
        where: { symbol: payload.symbol },
      });
      if (!market) {
        return res.status(400).json({ error: `Market ${payload.symbol} not found.` });
      }

      const result = await submitLimitOrder(
        {
          userId,
          symbol: payload.symbol,
          side: payload.side,
          price: payload.price,
          qty: payload.qty,
          mode: payload.mode as TradeMode,
          quoteFeeBps: payload.quoteFeeBps ?? "0",
          timeInForce: typeof payload.timeInForce === "string" ? payload.timeInForce : "GTC",
          source: "HUMAN",
        },
        prisma,
      );

      return res.status(201).json({ ok: true, ...result });
    } catch (error: any) {
      const message = error?.message ?? "Unable to place order";
      if (message.includes("insufficient") || message.includes("not balanced")) {
        return res.status(400).json({ error: message });
      }
      return res.status(400).json({ error: message });
    }
  }),
);

router.post(
  "/:orderId/cancel",
  requireRecentMfa(),
  cancelLimiter,
  auditPrivilegedRequest("ORDER_CANCEL_REQUESTED", "ORDER", (req) =>
    String(req.params.orderId),
  ),
  withIdempotency("HUMAN_ORDER_CANCEL", async (req, res) => {
    try {
      const userId = req.auth!.userId;
      const orderId = BigInt(String(req.params.orderId));

      const order = await prisma.order.findUnique({ where: { id: orderId } });

      if (!order || order.userId !== userId) {
        return res.status(404).json({ error: "Order not found." });
      }

      if (!canCancel(order.status)) {
        return res.status(409).json({
          error: `Cannot cancel order in status ${order.status}.`,
        });
      }

      const remainingQty = await getOrderRemainingQty(order, prisma);
      if (remainingQty.lessThanOrEqualTo(0)) {
        return res.status(409).json({
          error: "Order has no remaining quantity to cancel.",
        });
      }

      const result = await prisma.$transaction(async (tx) => {
        await releaseOrderOnCancel(
          {
            orderId: order.id,
            userId: order.userId,
            symbol: order.symbol,
            side: order.side,
            qty: remainingQty,
            price: order.price,
            mode: order.mode,
            reason: "CANCEL",
          },
          tx,
        );

        const cancelledOrder = await tx.order.update({
          where: { id: order.id },
          data: { status: ORDER_STATUS.CANCELLED },
        });

        return { order: cancelledOrder };
      });

      return res.json({
        ok: true,
        order: {
          id: result.order.id.toString(),
          symbol: result.order.symbol,
          side: result.order.side,
          price: result.order.price.toString(),
          qty: result.order.qty.toString(),
          status: result.order.status,
          mode: result.order.mode,
          timeInForce: result.order.timeInForce,
        },
        releasedQty: remainingQty.toString(),
      });
    } catch (error: any) {
      return res.status(400).json({ error: error?.message ?? "Unable to cancel order" });
    }
  }),
);

router.get("/:orderId", async (req, res) => {
  try {
    const userId = req.auth!.userId;
    const orderId = BigInt(String(req.params.orderId));

    const order = await prisma.order.findUnique({
      where: { id: orderId },
      include: {
        buys: { orderBy: { createdAt: "desc" }, take: 50 },
        sells: { orderBy: { createdAt: "desc" }, take: 50 },
      },
    });

    if (!order || order.userId !== userId) {
      return res.status(404).json({ error: "Order not found." });
    }

    const trades = [...order.buys, ...order.sells]
      .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
      .map((t) => ({
        id: t.id.toString(),
        price: t.price.toString(),
        qty: t.qty.toString(),
        createdAt: t.createdAt.toISOString(),
      }));

    const remainingQty = await getOrderRemainingQty(order, prisma);

    return res.json({
      ok: true,
      order: {
        id: order.id.toString(),
        symbol: order.symbol,
        side: order.side,
        price: order.price.toString(),
        qty: order.qty.toString(),
        status: order.status,
        mode: order.mode,
        timeInForce: order.timeInForce,
        createdAt: order.createdAt.toISOString(),
        remainingQty: remainingQty.toString(),
      },
      trades,
    });
  } catch (error: any) {
    return res.status(500).json({ error: error?.message ?? "Unable to fetch order" });
  }
});

export default router;
