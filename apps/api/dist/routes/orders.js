"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const library_1 = require("@prisma/client/runtime/library");
const zod_1 = require("zod");
const prisma_1 = require("../lib/prisma");
const submit_limit_order_1 = require("../lib/matching/submit-limit-order");
const ledger_1 = require("../lib/ledger");
const order_state_1 = require("../lib/ledger/order-state");
const time_in_force_1 = require("../lib/ledger/time-in-force");
const idempotency_1 = require("../lib/idempotency");
const require_auth_1 = require("../middleware/require-auth");
const audit_privileged_1 = require("../middleware/audit-privileged");
const simple_rate_limit_1 = require("../middleware/simple-rate-limit");
const router = (0, express_1.Router)();
const orderLimiter = (0, simple_rate_limit_1.simpleRateLimit)({
    keyPrefix: "orders:place",
    windowMs: 60 * 1000,
    max: 30,
});
const cancelLimiter = (0, simple_rate_limit_1.simpleRateLimit)({
    keyPrefix: "orders:cancel",
    windowMs: 60 * 1000,
    max: 60,
});
const placeOrderSchema = zod_1.z.object({
    symbol: zod_1.z.string().min(3).max(40),
    side: zod_1.z.enum(["BUY", "SELL"]),
    type: zod_1.z.enum(["LIMIT"]),
    price: zod_1.z.string().refine((v) => { try {
        return new library_1.Decimal(v).greaterThan(0);
    }
    catch {
        return false;
    } }, { message: "Price must be a positive number." }),
    qty: zod_1.z.string().refine((v) => { try {
        return new library_1.Decimal(v).greaterThan(0);
    }
    catch {
        return false;
    } }, { message: "Quantity must be a positive number." }),
    mode: zod_1.z.enum(["PAPER", "LIVE"]).optional().default("PAPER"),
    quoteFeeBps: zod_1.z.string().optional().default("0"),
    timeInForce: zod_1.z.enum(["GTC", "IOC", "FOK", "POST_ONLY"]).optional().default("GTC"),
});
router.use(require_auth_1.requireAuth);
router.get("/", async (req, res) => {
    try {
        const userId = req.auth.userId;
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
        const where = { userId };
        if (symbol)
            where.symbol = symbol;
        if (status)
            where.status = status;
        if (mode === "PAPER" || mode === "LIVE")
            where.mode = mode;
        const orders = await prisma_1.prisma.order.findMany({
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
    }
    catch (error) {
        return res.status(500).json({ error: error?.message ?? "Unable to fetch orders" });
    }
});
router.post("/", (0, require_auth_1.requireRecentMfa)(), (0, require_auth_1.requireLiveModeEligible)(), orderLimiter, (0, audit_privileged_1.auditPrivilegedRequest)("ORDER_PLACE_REQUESTED", "ORDER"), (0, idempotency_1.withIdempotency)("HUMAN_ORDER_PLACE", async (req, res) => {
    try {
        const userId = req.auth.userId;
        const payload = placeOrderSchema.parse(req.body);
        const preferredEngine = process.env.ALLOW_IN_MEMORY_MATCHING === "true"
            ? (req.get("x-matching-engine") ?? undefined)
            : undefined;
        const normalizedTimeInForce = (0, time_in_force_1.normalizeTimeInForce)(payload.timeInForce);
        const market = await prisma_1.prisma.market.findUnique({
            where: { symbol: payload.symbol },
        });
        if (!market) {
            return res.status(400).json({ error: `Market ${payload.symbol} not found.` });
        }
        const result = await (0, submit_limit_order_1.submitLimitOrder)({
            userId,
            symbol: payload.symbol,
            side: payload.side,
            price: payload.price,
            qty: payload.qty,
            mode: payload.mode,
            quoteFeeBps: payload.quoteFeeBps ?? "0",
            timeInForce: typeof payload.timeInForce === "string" ? payload.timeInForce : "GTC",
            source: "HUMAN",
            preferredEngine,
        }, prisma_1.prisma);
        return res.status(201).json({ ok: true, ...result });
    }
    catch (error) {
        const message = error?.message ?? "Unable to place order";
        if (message.includes("insufficient") || message.includes("not balanced")) {
            return res.status(400).json({ error: message });
        }
        return res.status(400).json({ error: message });
    }
}));
router.post("/:orderId/cancel", (0, require_auth_1.requireRecentMfa)(), cancelLimiter, (0, audit_privileged_1.auditPrivilegedRequest)("ORDER_CANCEL_REQUESTED", "ORDER", (req) => String(req.params.orderId)), (0, idempotency_1.withIdempotency)("HUMAN_ORDER_CANCEL", async (req, res) => {
    try {
        const userId = req.auth.userId;
        const orderId = BigInt(String(req.params.orderId));
        const order = await prisma_1.prisma.order.findUnique({ where: { id: orderId } });
        if (!order || order.userId !== userId) {
            return res.status(404).json({ error: "Order not found." });
        }
        if (!(0, order_state_1.canCancel)(order.status)) {
            return res.status(409).json({
                error: `Cannot cancel order in status ${order.status}.`,
            });
        }
        const remainingQty = await (0, ledger_1.getOrderRemainingQty)(order, prisma_1.prisma);
        if (remainingQty.lessThanOrEqualTo(0)) {
            return res.status(409).json({
                error: "Order has no remaining quantity to cancel.",
            });
        }
        const result = await prisma_1.prisma.$transaction(async (tx) => {
            await (0, ledger_1.releaseOrderOnCancel)({
                orderId: order.id,
                userId: order.userId,
                symbol: order.symbol,
                side: order.side,
                qty: remainingQty,
                price: order.price,
                mode: order.mode,
                reason: "CANCEL",
            }, tx);
            const cancelledOrder = await tx.order.update({
                where: { id: order.id },
                data: { status: order_state_1.ORDER_STATUS.CANCELLED },
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
    }
    catch (error) {
        return res.status(400).json({ error: error?.message ?? "Unable to cancel order" });
    }
}));
router.get("/:orderId", async (req, res) => {
    try {
        const userId = req.auth.userId;
        const orderId = BigInt(String(req.params.orderId));
        const order = await prisma_1.prisma.order.findUnique({
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
        const remainingQty = await (0, ledger_1.getOrderRemainingQty)(order, prisma_1.prisma);
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
    }
    catch (error) {
        return res.status(500).json({ error: error?.message ?? "Unable to fetch order" });
    }
});
exports.default = router;
