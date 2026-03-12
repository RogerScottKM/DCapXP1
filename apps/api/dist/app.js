"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createApp = void 0;
exports.makeApp = makeApp;
// apps/api/src/app.ts
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const zod_1 = require("zod");
const library_1 = require("@prisma/client/runtime/library");
const auth_1 = require("./lib/auth");
// Step-1 infra singletons
const ibac_1 = require("./middleware/ibac");
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
const mode_1 = require("./infra/mode");
/**  const m = raw.toUpperCase().trim(); */
/**  return m === "LIVE" ? "LIVE" : "PAPER"; */
function makeApp() {
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
    function normalizeKey(x) {
        if (typeof x === "string")
            return { symbol: x, mode: "PAPER" }; // legacy fallback
        if (x && typeof x.symbol === "string" && (x.mode === "PAPER" || x.mode === "LIVE"))
            return x;
        return null;
    }
    /** added to help define req, res .... 24/02/2026 */
    /** changed again ... >>> Agents to do the work! 05/03/2026 */
    app.use(async (req, res, next) => {
        try {
            // Agent-signed requests handle identity elsewhere
            if (req.header("x-agent-id"))
                return next();
            // Public / anonymous requests must be allowed through
            const usernameHeader = req.header("x-user");
            if (!usernameHeader)
                return next();
            const user = await prisma_1.prisma.user.findUnique({
                where: { username: String(usernameHeader) },
            });
            if (user) {
                const mode = (0, mode_1.resolveMode)(req);
                req.ctx = {
                    user: { id: user.id, username: user.username },
                    mode,
                };
            }
            return next();
        }
        catch (e) {
            console.error("[ctx middleware]", e);
            // IMPORTANT: never block public market-data routes here
            return next();
        }
    });
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
    /** agents to do the work  ..... >> added 05/03/2026 */
    app.post("/v1/agent/orders", (0, ibac_1.enforceMandate)("TRADE"), async (req, res) => {
        try {
            const payload = orderSchema.parse(req.body);
            const mode = (0, mode_1.resolveMode)(req);
            // ✅ IBAC middleware should have attached principal
            const principal = req.principal;
            if (!principal || principal.type !== "AGENT") {
                return res.status(401).json({ ok: false, error: "agent principal missing" });
            }
            // Resolve the owning user from principal.userId
            const user = await prisma_1.prisma.user.findUnique({ where: { id: principal.userId } });
            if (!user)
                return res.status(401).json({ ok: false, error: "unknown user for agent" });
            // Optional: attach ctx so your downstream code stays consistent
            req.ctx = { user: { id: user.id, username: user.username }, mode };
            // ---- From here down: same logic as your /v1/orders handler ----
            const symbol = payload.symbol.toUpperCase().trim();
            const events = [];
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
            const priceD = new library_1.Decimal(payload.price);
            const qtyD = new library_1.Decimal(payload.qty);
            if (priceD.lte(0) || qtyD.lte(0)) {
                return res.status(400).json({ ok: false, error: "price and qty must be > 0" });
            }
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
                    where: { userId: user.id, symbol, status: "OPEN", mode },
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
                        mode,
                        userId: user.id,
                        symbol,
                        side: payload.side,
                        price: new library_1.Decimal(payload.price),
                        qty: new library_1.Decimal(payload.qty),
                        status: "OPEN",
                    },
                });
                await match(tx, incoming, events);
                return await tx.order.findUnique({ where: { id: incoming.id } });
            });
            for (const e of events)
                bus_1.bus.emit(e.type, { symbol: e.symbol, mode: e.mode });
            return res.json({ ok: true, order: result });
        }
        catch (err) {
            return res.status(400).json({ ok: false, error: String(err?.message ?? err) });
        }
    });
    /** place order (and match) */
    app.post("/v1/orders", auth_1.requireAuth, async (req, res) => {
        try {
            console.log("[/v1/orders] body =", req.body);
            const payload = orderSchema.parse(req.body);
            const mode = (0, mode_1.resolveMode)(req); // ✅ ADD THIS
            const userId = req.userId;
            if (!userId)
                return res.status(401).json({ ok: false, error: "unauthorized" });
            const user = await prisma_1.prisma.user.findUnique({ where: { id: userId } });
            if (!user)
                return res.status(401).json({ ok: false, error: "unknown user" });
            const symbol = payload.symbol.toUpperCase().trim();
            const events = [];
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
                    where: { userId: user.id, symbol, status: "OPEN", mode }, // ✅ add mode
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
                        mode, // ✅ ADD THIS LINE
                        userId: user.id,
                        symbol,
                        side: payload.side,
                        price: new library_1.Decimal(payload.price),
                        qty: new library_1.Decimal(payload.qty),
                        status: "OPEN",
                    },
                });
                await match(tx, incoming, events);
                return await tx.order.findUnique({ where: { id: incoming.id } });
            });
            // ✅ emit only after commit
            for (const e of events)
                bus_1.bus.emit(e.type, { symbol: e.symbol, mode: e.mode });
            res.json({ ok: true, order: result });
        }
        catch (err) {
            res.status(400).json({ ok: false, error: String(err?.message ?? err) });
        }
    });
    /** cancel (scoped by user+mode) */
    app.post("/v1/orders/:id/cancel", auth_1.requireAuth, async (req, res) => {
        const idStr = req.params.id;
        if (!/^\d+$/.test(idStr))
            return res.status(400).json({ ok: false, error: "bad id" });
        const id = BigInt(idStr);
        const ctx = req.ctx;
        if (!ctx)
            return res.status(401).json({ ok: false, error: "unauthorized" });
        const userId = ctx.user.id; // ✅ string ((User.id is String/cuid))
        const mode = ctx.mode; // ✅ "PAPER" | "LIVE"
        const result = await prisma_1.prisma.order.updateMany({
            where: { id, userId, mode, status: "OPEN" },
            data: { status: "CANCELLED" },
        });
        if (result.count === 0) {
            const ord = await prisma_1.prisma.order.findFirst({
                where: { id, userId, mode },
                select: { status: true },
            });
            if (!ord)
                return res.status(404).json({ ok: false, error: "not found" });
            return res.status(400).json({ ok: false, error: "not open" });
        }
        const ord = await prisma_1.prisma.order.findFirst({
            where: { id, userId, mode },
            select: { symbol: true, mode: true },
        });
        if (ord)
            bus_1.bus.emit("orderbook", { symbol: ord.symbol, mode: ord.mode });
        return res.json({ ok: true });
    });
    /** ME + Balances */
    app.get("/v1/me", auth_1.requireAuth, async (req, res) => {
        try {
            const userId = req.userId;
            if (!userId)
                return res.status(401).json({ ok: false, error: "unauthorized" });
            const user = await prisma_1.prisma.user.findUnique({ where: { id: userId } });
            if (!user)
                return res.status(401).json({ ok: false, error: "unknown user" });
            const mode = (0, mode_1.resolveMode)(req);
            const full = await prisma_1.prisma.user.findUnique({
                where: { id: user.id },
                include: {
                    kyc: true,
                    balances: { where: { mode } }, // ✅ filter by mode
                },
            });
            res.json({ ok: true, mode, user: full });
        }
        catch (e) {
            res.status(400).json({ ok: false, error: String(e?.message ?? e) });
        }
    });
    app.get("/v1/balances", auth_1.requireAuth, async (req, res) => {
        try {
            const userId = req.userId;
            if (!userId)
                return res.status(401).json({ ok: false, error: "unauthorized" });
            const user = await prisma_1.prisma.user.findUnique({ where: { id: userId } });
            if (!user)
                return res.status(401).json({ ok: false, error: "unknown user" });
            const mode = (0, mode_1.resolveMode)(req);
            const balances = await prisma_1.prisma.balance.findMany({
                where: { userId: user.id, mode }, // ✅ filter by mode
            });
            res.json({ ok: true, mode, balances });
        }
        catch (e) {
            res.status(400).json({ ok: false, error: String(e?.message ?? e) });
        }
    });
    /** My Orders / Trades */
    app.get("/v1/my/orders", auth_1.requireAuth, async (req, res) => {
        try {
            const userId = req.userId;
            if (!userId)
                return res.status(401).json({ ok: false, error: "unauthorized" });
            const user = await prisma_1.prisma.user.findUnique({ where: { id: userId } });
            if (!user)
                return res.status(401).json({ ok: false, error: "unknown user" });
            const mode = (0, mode_1.resolveMode)(req); // ✅ add this
            const status = req.query.status;
            const where = { userId: user.id, mode }; // ✅ include mode
            if (status)
                where.status = status;
            const orders = await prisma_1.prisma.order.findMany({
                where,
                orderBy: { createdAt: "desc" },
                take: 200,
            });
            res.json({ ok: true, mode, orders });
        }
        catch (e) {
            res.status(400).json({ ok: false, error: String(e?.message ?? e) });
        }
    });
    app.get("/v1/my/trades", auth_1.requireAuth, async (req, res) => {
        try {
            const userId = req.userId;
            if (!userId)
                return res.status(401).json({ ok: false, error: "unauthorized" });
            const user = await prisma_1.prisma.user.findUnique({ where: { id: userId } });
            if (!user)
                return res.status(401).json({ ok: false, error: "unknown user" });
            const mode = (0, mode_1.resolveMode)(req); // ✅ add this
            const trades = await prisma_1.prisma.trade.findMany({
                where: {
                    mode, // ✅ include mode
                    OR: [
                        { buyOrder: { userId: user.id, mode } }, // ✅ mode-safe
                        { sellOrder: { userId: user.id, mode } }, // ✅ mode-safe
                    ],
                },
                orderBy: { createdAt: "desc" },
                take: 200,
                include: {
                    buyOrder: { select: { id: true, symbol: true, userId: true, mode: true } }, // optional but helpful
                    sellOrder: { select: { id: true, symbol: true, userId: true, mode: true } }, // optional but helpful
                },
            });
            res.json({ ok: true, mode, trades });
        }
        catch (e) {
            res.status(400).json({ ok: false, error: String(e?.message ?? e) });
        }
    });
    /** Faucet (demo funding) */
    app.post("/v1/faucet", auth_1.requireAuth, async (req, res) => {
        try {
            const userId = req.userId;
            if (!userId)
                return res.status(401).json({ ok: false, error: "unauthorized" });
            const user = await prisma_1.prisma.user.findUnique({ where: { id: userId } });
            if (!user)
                return res.status(401).json({ ok: false, error: "unknown user" });
            // ✅ resolve mode (PAPER by default)
            const mode = (0, mode_1.resolveMode)(req);
            // OPTIONAL: enforce faucet is PAPER-only (recommended for compliance)
            // if (mode === "LIVE") {
            //   return res.status(403).json({ ok: false, error: "Faucet is PAPER-only" });
            // }
            const { asset, amount } = req.body ?? {};
            if (!asset || !amount) {
                return res.status(400).json({ ok: false, error: "asset & amount required" });
            }
            const assetCode = String(asset).toUpperCase().trim();
            const amt = new library_1.Decimal(String(amount));
            await prisma_1.prisma.balance.upsert({
                where: { userId_mode_asset: { userId: user.id, mode, asset: assetCode } },
                update: { amount: { increment: amt } },
                create: { userId: user.id, mode, asset: assetCode, amount: amt },
            });
            res.json({ ok: true, mode });
        }
        catch (e) {
            res.status(400).json({ ok: false, error: String(e?.message ?? e) });
        }
    });
    /** KYC submit (demo) */
    app.post("/v1/kyc/submit", auth_1.requireAuth, async (req, res) => {
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
async function match(tx, order, events) {
    let remaining = new library_1.Decimal(order.qty);
    const limit = new library_1.Decimal(order.price);
    const isBuy = order.side === "BUY";
    while (remaining.gt(0)) {
        const counter = await tx.order.findFirst({
            where: {
                symbol: order.symbol,
                mode: order.mode,
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
                mode: order.mode,
                symbol: order.symbol,
                price: tradePrice,
                qty: tradeQty,
                buyOrderId: isBuy ? order.id : counter.id,
                sellOrderId: isBuy ? counter.id : order.id,
            },
        });
        // ✅ record events (emit after commit)
        events.push({ type: "trade", symbol: order.symbol, mode: order.mode });
        events.push({ type: "orderbook", symbol: order.symbol, mode: order.mode });
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
exports.createApp = makeApp;
