import { Router } from "express";

import { TradeMode, Prisma } from "@prisma/client";
import { z } from "zod";

import { prisma } from "../lib/prisma";
import { submitLimitOrder } from "../lib/matching/submit-limit-order";
import {
  executeLimitOrderAgainstBook,
  getOrderRemainingQty,
  reconcileOrderExecution,
  releaseResidualHoldAfterExecution,
  reconcileCumulativeFills,
  syncOrderStatusFromTrades,
  reconcileTradeSettlement,
  releaseOrderOnCancel,
  reserveOrderOnPlacement,
  settleMatchedTrade,
} from "../lib/ledger";
import { canCancel, ORDER_STATUS } from "../lib/ledger/order-state";
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
  quoteFeeBps: z.string().optional(),
});

const fillSchema = z.object({
  buyOrderId: z.union([z.string(), z.number(), z.bigint()]),
  sellOrderId: z.union([z.string(), z.number(), z.bigint()]),
  symbol: z.string().min(3).max(40),
  qty: z.string(),
  price: z.string(),
  mode: z.enum(["PAPER", "LIVE"]).optional().default("PAPER"),
  quoteFee: z.string().optional(),
});

router.post("/orders", enforceMandate("TRADE"), async (req: any, res) => {
  try {
    const payload = orderSchema.parse(req.body);
    const limitPrice = payload.price;
    if (!limitPrice) {
      return res.status(400).json({ error: "LIMIT orders require price." });
    }
    const principal = req.principal;

    if (!principal || principal.type !== "AGENT") {
      return res.status(401).json({ error: "Agent principal missing" });
    }

    if (payload.type !== "LIMIT") {
      return res.status(400).json({ error: "Phase 2D only wires LIMIT order execution and ledger booking." });
    }

    if (!payload.price) {
      return res.status(400).json({ error: "LIMIT orders require price." });
    }

    const result = await submitLimitOrder(
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

      return res.json({ ok: true, ...result });
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

    const remainingQty = await getOrderRemainingQty(order, prisma);

    if (!canCancel(order.status)) {
      return res.status(409).json({
        error: `Cannot cancel order in status ${order.status}.`,
      });
    }

    if (remainingQty.lessThanOrEqualTo(0)) {
      return res.status(409).json({ error: "Order has no remaining quantity to cancel." });
    }

    const [ledgerRelease, cancelledOrder] = await prisma.$transaction(async (tx) => {
      const release = await releaseOrderOnCancel(
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

      const updated = await tx.order.update({
        where: { id: order.id },
        data: { status: ORDER_STATUS.CANCELLED },
      });

      return [release, updated] as const;
    });

    return res.json({ ok: true, order: cancelledOrder, ledgerRelease, remainingQty: remainingQty.toString() });
  } catch (error: any) {
    return res.status(400).json({ error: error?.message ?? "Unable to cancel order" });
  }
});

router.post("/fills/demo", enforceMandate("TRADE"), async (req: any, res) => {
  try {
    const principal = req.principal;
    if (!principal || principal.type !== "AGENT") {
      return res.status(401).json({ error: "Agent principal missing" });
    }

    const payload = fillSchema.parse(req.body);

    const result = await prisma.$transaction(async (tx) => {
      const buyOrderId = BigInt(String(payload.buyOrderId));
      const sellOrderId = BigInt(String(payload.sellOrderId));

      const [buyOrder, sellOrder] = await Promise.all([
        tx.order.findUnique({ where: { id: buyOrderId } }),
        tx.order.findUnique({ where: { id: sellOrderId } }),
      ]);

      if (!buyOrder || !sellOrder) {
        throw new Error("Both buy and sell orders are required.");
      }
      if (buyOrder.side !== "BUY" || sellOrder.side !== "SELL") {
        throw new Error("Fill settlement requires a BUY order and a SELL order.");
      }
      if (buyOrder.symbol !== payload.symbol || sellOrder.symbol !== payload.symbol) {
        throw new Error("Both orders must match the fill symbol.");
      }
      if (buyOrder.mode !== (payload.mode as TradeMode) || sellOrder.mode !== (payload.mode as TradeMode)) {
        throw new Error("Both orders must match the fill mode.");
      }
      if (buyOrder.status !== "OPEN" || sellOrder.status !== "OPEN") {
        throw new Error("Only OPEN orders can be settled in the Phase 2C/2D demo fill path.");
      }

      const trade = await tx.trade.create({
        data: {
          symbol: payload.symbol,
          price: new Prisma.Decimal(payload.price!),
          qty: new Prisma.Decimal(payload.qty),
          mode: payload.mode as TradeMode,
          buyOrderId: buyOrder.id,
          sellOrderId: sellOrder.id,
        },
      });

      const ledgerSettlement = await settleMatchedTrade(
        {
          tradeRef: trade.id.toString(),
          buyOrderId: buyOrder.id,
          sellOrderId: sellOrder.id,
          symbol: payload.symbol,
          qty: payload.qty,
          price: payload.price!,
          mode: payload.mode as TradeMode,
          quoteFee: payload.quoteFee ?? "0",
        },
        tx,
      );

      const updatedBuyOrder = await syncOrderStatusFromTrades(buyOrder.id, tx);
      const updatedSellOrder = await syncOrderStatusFromTrades(sellOrder.id, tx);

      const buyFillCheck = await reconcileCumulativeFills(updatedBuyOrder.id, tx);
      const sellFillCheck = await reconcileCumulativeFills(updatedSellOrder.id, tx);

      const buyHeldRelease =
        updatedBuyOrder.status === "FILLED"
          ? await releaseResidualHoldAfterExecution(
              {
                orderId: updatedBuyOrder.id,
                userId: updatedBuyOrder.userId,
                symbol: updatedBuyOrder.symbol,
                side: updatedBuyOrder.side,
                mode: updatedBuyOrder.mode,
                orderQty: updatedBuyOrder.qty,
                limitPrice: updatedBuyOrder.price,
                cumulativeFilledQty: buyFillCheck.cumulativeFilledQty,
                weightedExecutedQuote: new Prisma.Decimal(payload.qty).mul(
                  new Prisma.Decimal(payload.price),
                ),
              },
              tx,
            )
          : null;

      const reconciliation = await reconcileTradeSettlement(trade.id, tx);
      const buyOrderReconciliation = await reconcileOrderExecution(updatedBuyOrder.id, tx);
      const sellOrderReconciliation = await reconcileOrderExecution(updatedSellOrder.id, tx);

      return {
        trade,
        ledgerSettlement,
        reconciliation,
        buyOrder: updatedBuyOrder,
        sellOrder: updatedSellOrder,
        buyOrderReconciliation,
        sellOrderReconciliation,
        buyFillCheck,
        sellFillCheck,
        buyHeldRelease,
      };
    });

    return res.json({ ok: true, ...result });
  } catch (error: any) {
    return res.status(400).json({ error: error?.message ?? "Unable to settle fill" });
  }
});

export default router;
