"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const client_1 = require("@prisma/client");
const zod_1 = require("zod");
const prisma_1 = require("../lib/prisma");
const ledger_1 = require("../lib/ledger");
const order_state_1 = require("../lib/ledger/order-state");
const ibac_1 = require("../middleware/ibac");
const router = (0, express_1.Router)();
const orderSchema = zod_1.z.object({
    symbol: zod_1.z.string().min(3).max(40),
    side: zod_1.z.enum(["BUY", "SELL"]),
    type: zod_1.z.enum(["LIMIT", "MARKET"]),
    qty: zod_1.z.string(),
    price: zod_1.z.string().optional(),
    tif: zod_1.z.enum(["GTC", "IOC", "FOK", "POST_ONLY"]).optional(),
    mode: zod_1.z.enum(["PAPER", "LIVE"]).optional().default("PAPER"),
    quoteFeeBps: zod_1.z.string().optional(),
});
const fillSchema = zod_1.z.object({
    buyOrderId: zod_1.z.union([zod_1.z.string(), zod_1.z.number(), zod_1.z.bigint()]),
    sellOrderId: zod_1.z.union([zod_1.z.string(), zod_1.z.number(), zod_1.z.bigint()]),
    symbol: zod_1.z.string().min(3).max(40),
    qty: zod_1.z.string(),
    price: zod_1.z.string(),
    mode: zod_1.z.enum(["PAPER", "LIVE"]).optional().default("PAPER"),
    quoteFee: zod_1.z.string().optional(),
});
router.post("/orders", (0, ibac_1.enforceMandate)("TRADE"), async (req, res) => {
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
        const result = await prisma_1.prisma.$transaction(async (tx) => {
            const order = await tx.order.create({
                data: {
                    symbol: payload.symbol,
                    side: payload.side,
                    price: new client_1.Prisma.Decimal(payload.price),
                    qty: new client_1.Prisma.Decimal(payload.qty),
                    status: "OPEN",
                    mode: payload.mode,
                    userId: principal.userId,
                },
            });
            const ledgerReservation = await (0, ledger_1.reserveOrderOnPlacement)({
                orderId: order.id,
                userId: principal.userId,
                symbol: payload.symbol,
                side: payload.side,
                qty: payload.qty,
                price: payload.price,
                mode: payload.mode,
            }, tx);
            const execution = await (0, ledger_1.executeLimitOrderAgainstBook)({
                orderId: order.id,
                quoteFeeBps: payload.quoteFeeBps ?? "0",
            }, tx);
            const orderReconciliation = await (0, ledger_1.reconcileOrderExecution)(order.id, tx);
            const cumulativeFillCheck = await (0, ledger_1.reconcileCumulativeFills)(order.id, tx);
            return { order, ledgerReservation, execution, orderReconciliation, cumulativeFillCheck };
        });
        await (0, ibac_1.bumpOrdersPlaced)(principal.mandateId ?? principal.mandate?.id);
        return res.json({ ok: true, ...result });
    }
    catch (error) {
        return res.status(400).json({ error: error?.message ?? "Unable to place order" });
    }
});
router.post("/orders/:orderId/cancel", (0, ibac_1.enforceMandate)("TRADE"), async (req, res) => {
    try {
        const principal = req.principal;
        if (!principal || principal.type !== "AGENT") {
            return res.status(401).json({ error: "Agent principal missing" });
        }
        const orderId = BigInt(String(req.params.orderId));
        const order = await prisma_1.prisma.order.findUnique({ where: { id: orderId } });
        if (!order || order.userId !== principal.userId) {
            return res.status(404).json({ error: "Order not found" });
        }
        const remainingQty = await (0, ledger_1.getOrderRemainingQty)(order, prisma_1.prisma);
        if (!(0, order_state_1.canCancel)(order.status)) {
            return res.status(409).json({
                error: `Cannot cancel order in status ${order.status}.`,
            });
        }
        if (remainingQty.lessThanOrEqualTo(0)) {
            return res.status(409).json({ error: "Order has no remaining quantity to cancel." });
        }
        const [ledgerRelease, cancelledOrder] = await prisma_1.prisma.$transaction(async (tx) => {
            const release = await (0, ledger_1.releaseOrderOnCancel)({
                orderId: order.id,
                userId: order.userId,
                symbol: order.symbol,
                side: order.side,
                qty: remainingQty,
                price: order.price,
                mode: order.mode,
                reason: "CANCEL",
            }, tx);
            const updated = await tx.order.update({
                where: { id: order.id },
                data: { status: order_state_1.ORDER_STATUS.CANCELLED },
            });
            return [release, updated];
        });
        return res.json({ ok: true, order: cancelledOrder, ledgerRelease, remainingQty: remainingQty.toString() });
    }
    catch (error) {
        return res.status(400).json({ error: error?.message ?? "Unable to cancel order" });
    }
});
router.post("/fills/demo", (0, ibac_1.enforceMandate)("TRADE"), async (req, res) => {
    try {
        const principal = req.principal;
        if (!principal || principal.type !== "AGENT") {
            return res.status(401).json({ error: "Agent principal missing" });
        }
        const payload = fillSchema.parse(req.body);
        const result = await prisma_1.prisma.$transaction(async (tx) => {
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
            if (buyOrder.mode !== payload.mode || sellOrder.mode !== payload.mode) {
                throw new Error("Both orders must match the fill mode.");
            }
            if (buyOrder.status !== "OPEN" || sellOrder.status !== "OPEN") {
                throw new Error("Only OPEN orders can be settled in the Phase 2C/2D demo fill path.");
            }
            const trade = await tx.trade.create({
                data: {
                    symbol: payload.symbol,
                    price: new client_1.Prisma.Decimal(payload.price),
                    qty: new client_1.Prisma.Decimal(payload.qty),
                    mode: payload.mode,
                    buyOrderId: buyOrder.id,
                    sellOrderId: sellOrder.id,
                },
            });
            const ledgerSettlement = await (0, ledger_1.settleMatchedTrade)({
                tradeRef: trade.id.toString(),
                buyOrderId: buyOrder.id,
                sellOrderId: sellOrder.id,
                symbol: payload.symbol,
                qty: payload.qty,
                price: payload.price,
                mode: payload.mode,
                quoteFee: payload.quoteFee ?? "0",
            }, tx);
            const updatedBuyOrder = await (0, ledger_1.syncOrderStatusFromTrades)(buyOrder.id, tx);
            const updatedSellOrder = await (0, ledger_1.syncOrderStatusFromTrades)(sellOrder.id, tx);
            const buyFillCheck = await (0, ledger_1.reconcileCumulativeFills)(updatedBuyOrder.id, tx);
            const sellFillCheck = await (0, ledger_1.reconcileCumulativeFills)(updatedSellOrder.id, tx);
            const buyHeldRelease = updatedBuyOrder.status === "FILLED"
                ? await (0, ledger_1.releaseResidualHoldAfterExecution)({
                    orderId: updatedBuyOrder.id,
                    userId: updatedBuyOrder.userId,
                    symbol: updatedBuyOrder.symbol,
                    side: updatedBuyOrder.side,
                    mode: updatedBuyOrder.mode,
                    orderQty: updatedBuyOrder.qty,
                    limitPrice: updatedBuyOrder.price,
                    cumulativeFilledQty: buyFillCheck.cumulativeFilledQty,
                    weightedExecutedQuote: new client_1.Prisma.Decimal(payload.qty).mul(new client_1.Prisma.Decimal(payload.price)),
                }, tx)
                : null;
            const reconciliation = await (0, ledger_1.reconcileTradeSettlement)(trade.id, tx);
            const buyOrderReconciliation = await (0, ledger_1.reconcileOrderExecution)(updatedBuyOrder.id, tx);
            const sellOrderReconciliation = await (0, ledger_1.reconcileOrderExecution)(updatedSellOrder.id, tx);
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
    }
    catch (error) {
        return res.status(400).json({ error: error?.message ?? "Unable to settle fill" });
    }
});
exports.default = router;
