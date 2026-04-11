import { Router } from "express";

import { TradeMode, Prisma } from "@prisma/client";
import { z } from "zod";

import { prisma } from "../lib/prisma";
import {
  releaseOrderOnCancel,
  reserveOrderOnPlacement,
} from "../lib/ledger/order-lifecycle";
import { enforceMandate, bumpOrdersPlaced } from "../middleware/ibac";

const router = Router();

const orderSchema = z.object({
  symbol: z.string().min(3).max(40),
  side: z.enum(["BUY", "SELL"]),
  type: z.enum(["LIMIT", "MARKET"]),
  qty: z.string(),
  price: z.string().optional(),
  tif: z.enum(["GTC", "IOC", "FOK", "POST_ONLY"]).optional(),
  mode: z.enum(["PAPER", "LIVE"]).optional().default("PAPER"),
});

router.post("/orders", enforceMandate("TRADE"), async (req: any, res) => {
  try {
    const payload = orderSchema.parse(req.body);
    const principal = req.principal;

    if (!principal || principal.type !== "AGENT") {
      return res.status(401).json({ error: "Agent principal missing" });
    }

    if (payload.type !== "LIMIT") {
      return res.status(400).json({ error: "Phase 2B only wires LIMIT order ledger booking." });
    }

    if (!payload.price) {
      return res.status(400).json({ error: "LIMIT orders require price." });
    }

    const order = await prisma.order.create({
      data: {
        symbol: payload.symbol,
        side: payload.side,
        price: new Prisma.Decimal(payload.price),
        qty: new Prisma.Decimal(payload.qty),
        status: "OPEN",
        mode: payload.mode as TradeMode,
        userId: principal.userId,
      },
    });

    const ledgerReservation = await reserveOrderOnPlacement({
      orderId: order.id,
      userId: principal.userId,
      symbol: payload.symbol,
      side: payload.side,
      qty: payload.qty,
      price: payload.price,
      mode: payload.mode as TradeMode,
    });

    await bumpOrdersPlaced(principal.mandateId ?? principal.mandate?.id);

    return res.json({ ok: true, order, ledgerReservation });
  } catch (error: any) {
    return res.status(400).json({ error: error?.message ?? "Unable to place order" });
  }
});

router.post("/orders/:orderId/cancel", enforceMandate("TRADE"), async (req: any, res) => {
  try {
    const principal = req.principal;
    if (!principal || principal.type !== "AGENT") {
      return res.status(401).json({ error: "Agent principal missing" });
    }

    const orderId = BigInt(String(req.params.orderId));
    const order = await prisma.order.findUnique({ where: { id: orderId } });

    if (!order || order.userId !== principal.userId) {
      return res.status(404).json({ error: "Order not found" });
    }

    if (order.status !== "OPEN") {
      return res.status(409).json({ error: "Only OPEN orders can be cancelled" });
    }

    const [ledgerRelease, cancelledOrder] = await prisma.$transaction(async (tx) => {
      const release = await releaseOrderOnCancel({
        orderId: order.id,
        userId: order.userId,
        symbol: order.symbol,
        side: order.side,
        qty: order.qty,
        price: order.price,
        mode: order.mode,
        reason: "CANCEL",
      }, tx);

      const updated = await tx.order.update({
        where: { id: order.id },
        data: { status: "CANCELLED" },
      });

      return [release, updated] as const;
    });

    return res.json({ ok: true, order: cancelledOrder, ledgerRelease });
  } catch (error: any) {
    return res.status(400).json({ error: error?.message ?? "Unable to cancel order" });
  }
});

export default router;
