"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createApp = createApp;
// apps/api/src/app.ts
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const zod_1 = require("zod");
const library_1 = require("@prisma/client/runtime/library");
// Step-1 infra singletons
const prisma_1 = require("./infra/prisma");
const bus_1 = require("./infra/bus");
const json_1 = require("./infra/json");
const symbolControl_1 = require("./infra/symbolControl");
const riskLimits_1 = require("./infra/riskLimits");
// Modular routes
const agentic_1 = __importDefault(require("./routes/agentic"));
const market_1 = __importDefault(require("./routes/market"));
const stream_1 = __importDefault(require("./routes/stream"));
const admin_1 = __importDefault(require("./routes/admin"));
const flags_1 = __importDefault(require("./routes/flags"));
function createApp() {
    const app = (0, express_1.default)();
    app.set("json replacer", json_1.jsonReplacer);
    app.use((0, cors_1.default)({ origin: true }));
    app.use(express_1.default.json());
    /** util: resolve user from header (defaults to demo) */
    async function requireUser(req) {
        const username = String(req.header("x-user") ?? "demo");
        const user = await prisma_1.prisma.user.findUnique({ where: { username } });
        if (!user)
            throw new Error(`unknown user '${username}'`);
        return user;
    }
    /** health */
    app.get("/health", (_req, res) => {
        res.json({ ok: true, ts: new Date().toISOString() });
    });
    // ====== ROUTE MOUNTS ======
    app.use("/api/v1/ui", agentic_1.default);
    app.use("/v1/ui", agentic_1.default);
    app.use("/api/v1/market", market_1.default);
    app.use("/v1", stream_1.default);
    app.use("/api/v1/admin", admin_1.default);
    app.use("/api/v1/admin", flags_1.default); // /api/v1/admin/flags/...
    // ====== CORE WRITE ENDPOINTS ======
    /** markets */
    app.get("/v1/markets", async (_req, res) => {
        const markets = await prisma_1.prisma.market.findMany({ orderBy: { symbol: "asc" } });
        res.json({ markets });
    });
    /** schema for placing an order */
    const orderSchema = zod_1.z.object({
        symbol: zod_1.z.string().min(1),
        side: zod_1.z.enum(["BUY", "SELL"]),
        price: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).transform((v) => v.toString()),
        qty: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).transform((v) => v.toString()),
    });
    /** place order (and match) */
    app.post("/v1/orders", async (req, res) => {
        try {
            const payload = orderSchema.parse(req.body);
            const user = await requireUser(req);
            const symbol = payload.symbol.toUpperCase().trim();
            // 1) Kill-switch (per symbol)
            const control = symbolControl_1.symbolControl.get(symbol);
            if (!(0, symbolControl_1.isNewOrderAllowed)(control.mode)) {
                return res.status(423).json({
                    ok: false,
                    symbol,
                    mode: control.mode,
                    control,
                    error: (0, symbolControl_1.explainMode)(control.mode),
                });
            }
            // 2) Basic numeric sanity
            const priceD = new library_1.Decimal(payload.price);
            const qtyD = new library_1.Decimal(payload.qty);
            if (priceD.lte(0) || qtyD.lte(0)) {
                return res.status(400).json({ ok: false, error: "price and qty must be > 0" });
            }
            // 3) Risk limits (per symbol)
            const limits = riskLimits_1.riskLimits.get(symbol);
            if (limits.maxOrderQty) {
                const maxQ = new library_1.Decimal(limits.maxOrderQty);
                if (qtyD.gt(maxQ)) {
                    return res.status(429).json({
                        ok: false,
                        symbol,
                        code: "MAX_ORDER_QTY",
                        error: `Order qty exceeds maxOrderQty (${maxQ.toString()})`,
                        limits,
                    });
                }
            }
            if (limits.maxOrderNotional) {
                const maxN = new library_1.Decimal(limits.maxOrderNotional);
                const notional = priceD.mul(qtyD);
                if (notional.gt(maxN)) {
                    return res.status(429).json({
                        ok: false,
                        symbol,
                        code: "MAX_ORDER_NOTIONAL",
                        error: `Order notional exceeds maxOrderNotional (${maxN.toString()})`,
                        limits,
                        notional: notional.toString(),
                    });
                }
            }
            if (typeof limits.maxOpenOrders === "number") {
                const openCount = await prisma_1.prisma.order.count({
                    where: { userId: user.id, symbol, status: "OPEN" },
                });
                if (openCount >= limits.maxOpenOrders) {
                    return res.status(429).json({
                        ok: false,
                        symbol,
                        code: "MAX_OPEN_ORDERS",
                        error: `Open orders limit reached (${limits.maxOpenOrders})`,
                        limits,
                        openCount,
                    });
                }
            }
            const result = await prisma_1.prisma.$transaction(async (tx) => {
                const incoming = await tx.order.create({
                    data: {
                        userId: user.id,
                        symbol,
                        side: payload.side,
                        price: new library_1.Decimal(payload.price),
                        qty: new library_1.Decimal(payload.qty),
                        status: "OPEN",
                    },
                });
                await match(tx, incoming);
                return await tx.order.findUnique({ where: { id: incoming.id } });
            });
            bus_1.bus.emit("orderbook", symbol);
            res.json({ ok: true, order: result });
        }
        catch (err) {
            console.error(err);
            res.status(400).json({ ok: false, error: String(err?.message ?? err) });
        }
    });
    /** cancel */
    app.post("/v1/orders/:id/cancel", async (req, res) => {
        const id = BigInt(req.params.id);
        const ord = await prisma_1.prisma.order.findUnique({ where: { id } });
        if (!ord)
            return res.status(404).json({ ok: false, error: "not found" });
        if (ord.status !== "OPEN") {
            return res.status(400).json({ ok: false, error: "not open" });
        }
        // cancels always allowed
        await prisma_1.prisma.order.update({ where: { id }, data: { status: "CANCELLED" } });
        bus_1.bus.emit("orderbook", ord.symbol);
        res.json({ ok: true });
    });
    /** ME + Balances */
    app.get("/v1/me", async (req, res) => {
        try {
            const user = await requireUser(req);
            const full = await prisma_1.prisma.user.findUnique({
                where: { id: user.id },
                include: { kyc: true, balances: true },
            });
            res.json({ ok: true, user: full });
        }
        catch (e) {
            res.status(400).json({ ok: false, error: String(e?.message ?? e) });
        }
    });
    app.get("/v1/balances", async (req, res) => {
        try {
            const user = await requireUser(req);
            const balances = await prisma_1.prisma.balance.findMany({ where: { userId: user.id } });
            res.json({ ok: true, balances });
        }
        catch (e) {
            res.status(400).json({ ok: false, error: String(e?.message ?? e) });
        }
    });
    /** My Orders / Trades */
    app.get("/v1/my/orders", async (req, res) => {
        try {
            const user = await requireUser(req);
            const status = req.query.status;
            const where = { userId: user.id };
            if (status)
                where.status = status;
            const orders = await prisma_1.prisma.order.findMany({
                where,
                orderBy: { createdAt: "desc" },
                take: 200,
            });
            res.json({ ok: true, orders });
        }
        catch (e) {
            res.status(400).json({ ok: false, error: String(e?.message ?? e) });
        }
    });
    app.get("/v1/my/trades", async (req, res) => {
        try {
            const user = await requireUser(req);
            const trades = await prisma_1.prisma.trade.findMany({
                where: {
                    OR: [{ buyOrder: { userId: user.id } }, { sellOrder: { userId: user.id } }],
                },
                orderBy: { createdAt: "desc" },
                take: 200,
                include: {
                    buyOrder: { select: { id: true, symbol: true, userId: true } },
                    sellOrder: { select: { id: true, symbol: true, userId: true } },
                },
            });
            res.json({ ok: true, trades });
        }
        catch (e) {
            res.status(400).json({ ok: false, error: String(e?.message ?? e) });
        }
    });
    /** Faucet (demo funding) */
    app.post("/v1/faucet", async (req, res) => {
        try {
            const user = await requireUser(req);
            const { asset, amount } = req.body ?? {};
            if (!asset || !amount) {
                return res.status(400).json({ ok: false, error: "asset & amount required" });
            }
            const amt = new library_1.Decimal(String(amount));
            await prisma_1.prisma.balance.upsert({
                where: { userId_asset: { userId: user.id, asset } },
                update: { amount: { increment: amt } },
                create: { userId: user.id, asset, amount: amt },
            });
            res.json({ ok: true });
        }
        catch (e) {
            res.status(400).json({ ok: false, error: String(e?.message ?? e) });
        }
    });
    /** KYC submit (demo) */
    app.post("/v1/kyc/submit", async (req, res) => {
        try {
            const user = await requireUser(req);
            const { legalName, country, dob, docType, docHash } = req.body ?? {};
            if (!legalName || !country || !dob || !docType || !docHash) {
                return res.status(400).json({ ok: false, error: "missing fields" });
            }
            const rec = await prisma_1.prisma.kyc.upsert({
                where: { userId: user.id },
                update: {
                    legalName,
                    country,
                    dob: new Date(dob),
                    docType,
                    docHash,
                    status: "PENDING",
                    updatedAt: new Date(),
                },
                create: {
                    userId: user.id,
                    legalName,
                    country,
                    dob: new Date(dob),
                    docType,
                    docHash,
                    status: "PENDING",
                    riskScore: new library_1.Decimal(0),
                },
            });
            res.json({ ok: true, kyc: rec });
        }
        catch (e) {
            res.status(400).json({ ok: false, error: String(e?.message ?? e) });
        }
    });
    return app;
}
/** price-time-priority matching */
async function match(tx, order) {
    let remaining = new library_1.Decimal(order.qty);
    const limit = new library_1.Decimal(order.price);
    const isBuy = order.side === "BUY";
    while (remaining.gt(0)) {
        const counter = await tx.order.findFirst({
            where: {
                symbol: order.symbol,
                status: "OPEN",
                side: isBuy ? "SELL" : "BUY",
                price: isBuy ? { lte: limit } : { gte: limit },
            },
            orderBy: [{ price: isBuy ? "asc" : "desc" }, { createdAt: "asc" }],
        });
        if (!counter)
            break;
        const tradeQty = library_1.Decimal.min(remaining, counter.qty);
        const tradePrice = counter.price;
        await tx.trade.create({
            data: {
                symbol: order.symbol,
                price: tradePrice,
                qty: tradeQty,
                buyOrderId: isBuy ? order.id : counter.id,
                sellOrderId: isBuy ? counter.id : order.id,
            },
        });
        bus_1.bus.emit("trade", order.symbol);
        const counterLeft = counter.qty.minus(tradeQty);
        await tx.order.update({
            where: { id: counter.id },
            data: counterLeft.lte(0)
                ? { status: "FILLED", qty: new library_1.Decimal(0) }
                : { qty: counterLeft },
        });
        remaining = remaining.minus(tradeQty);
    }
    await tx.order.update({
        where: { id: order.id },
        data: remaining.lte(0)
            ? { status: "FILLED", qty: new library_1.Decimal(0) }
            : { qty: remaining },
    });
}
