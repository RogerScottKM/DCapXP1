"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
// apps/api/src/server.ts
const plan_1 = require("./agentic/plan");
require("dotenv/config");
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const node_events_1 = require("node:events");
const zod_1 = require("zod");
const client_1 = require("@prisma/client");
const library_1 = require("@prisma/client/runtime/library");
const app = (0, express_1.default)();
/** JSON replacer that makes BigInt/Decimal printable */
const jsonReplacer = (_k, v) => {
    if (typeof v === 'bigint')
        return v.toString();
    if (v instanceof library_1.Decimal)
        return v.toString();
    return v;
};
app.set('json replacer', jsonReplacer);
app.use((0, cors_1.default)({ origin: true }));
app.use(express_1.default.json());
/** tiny event bus for streaming orderbook updates */
const bus = new node_events_1.EventEmitter();
bus.setMaxListeners(0);
const prisma = new client_1.PrismaClient();
const PORT = Number(process.env.PORT ?? process.env.API_PORT ?? 4010);
/** util: safely stringify (for SSE) */
function safeStringify(obj) {
    return JSON.stringify(obj, jsonReplacer);
}
/** util: resolve user from header (defaults to demo) */
async function requireUser(req) {
    const username = String(req.header('x-user') ?? 'demo');
    const user = await prisma.user.findUnique({ where: { username } });
    if (!user)
        throw new Error(`unknown user '${username}'`);
    return user;
}
/** health */
app.get('/health', (_req, res) => {
    res.json({ ok: true, ts: new Date().toISOString() });
});
/** UI Plan (agentic v2) */
app.get(['/api/v1/ui/plan', '/v1/ui/plan'], (req, res) => {
    const plan = (0, plan_1.generateUIPlan)({
        userId: req.query.userId,
        intent: req.query.intent,
        symbol: req.query.symbol,
    });
    res.json(plan);
});
/** markets */
app.get('/v1/markets', async (_req, res) => {
    const markets = await prisma.market.findMany({ orderBy: { symbol: 'asc' } });
    res.json({ markets });
});
/** schema for placing an order */
const orderSchema = zod_1.z.object({
    symbol: zod_1.z.string().min(1),
    side: zod_1.z.enum(['BUY', 'SELL']),
    price: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).transform((v) => v.toString()),
    qty: zod_1.z.union([zod_1.z.number(), zod_1.z.string()]).transform((v) => v.toString()),
});
/** place order (and match) */
app.post('/v1/orders', async (req, res) => {
    try {
        const payload = orderSchema.parse(req.body);
        const user = await requireUser(req);
        const result = await prisma.$transaction(async (tx) => {
            // create incoming order
            const incoming = await tx.order.create({
                data: {
                    userId: user.id,
                    symbol: payload.symbol,
                    side: payload.side,
                    price: new library_1.Decimal(payload.price),
                    qty: new library_1.Decimal(payload.qty),
                    status: 'OPEN',
                },
            });
            // run matcher
            await match(tx, incoming);
            // return final state
            return await tx.order.findUnique({ where: { id: incoming.id } });
        });
        // notify orderbook listeners
        bus.emit('orderbook', result.symbol);
        res.json({ ok: true, order: result });
    }
    catch (err) {
        console.error(err);
        res.status(400).json({ ok: false, error: String(err?.message ?? err) });
    }
});
/** cancel */
app.post('/v1/orders/:id/cancel', async (req, res) => {
    const id = BigInt(req.params.id);
    const ord = await prisma.order.findUnique({ where: { id } });
    if (!ord)
        return res.status(404).json({ ok: false, error: 'not found' });
    if (ord.status !== 'OPEN') {
        return res.status(400).json({ ok: false, error: 'not open' });
    }
    await prisma.order.update({ where: { id }, data: { status: 'CANCELLED' } });
    bus.emit('orderbook', ord.symbol);
    res.json({ ok: true });
});
/** orderbook (top 20) */
app.get('/v1/orderbook/:symbol', async (req, res) => {
    const symbol = req.params.symbol.toUpperCase();
    const [bids, asks] = await Promise.all([
        prisma.order.findMany({
            where: { symbol, status: 'OPEN', side: 'BUY' },
            orderBy: [{ price: 'desc' }, { createdAt: 'asc' }],
            take: 20,
        }),
        prisma.order.findMany({
            where: { symbol, status: 'OPEN', side: 'SELL' },
            orderBy: [{ price: 'asc' }, { createdAt: 'asc' }],
            take: 20,
        }),
    ]);
    res.json({ bids, asks });
});
/** recent trades */
app.get('/v1/trades/:symbol', async (req, res) => {
    const symbol = req.params.symbol.toUpperCase();
    const trades = await prisma.trade.findMany({
        where: { symbol },
        orderBy: { createdAt: 'desc' },
        take: 50,
    });
    res.json({ trades });
});
/** SSE stream: initial snapshot + live orderbook updates */
app.get('/v1/stream/:symbol', async (req, res) => {
    const symbol = req.params.symbol.toUpperCase();
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.flushHeaders?.();
    const send = (event, data) => {
        res.write(`event: ${event}\n`);
        res.write(`data: ${safeStringify(data)}\n\n`);
    };
    const onTrade = async (s) => {
        if (s === symbol) {
            // send latest trades array; Candles will bucket to OHLC
            send('trades', await getRecentTrades(symbol));
        }
    };
    bus.on('trade', onTrade);
    req.on('close', () => bus.off('trade', onTrade));
    // initial snapshot
    send('snapshot', {
        orderbook: await getOrderbook(symbol),
        trades: await getRecentTrades(symbol),
    });
    // update on book changes for this symbol
    const onBook = async (s) => {
        if (s === symbol)
            send('orderbook', await getOrderbook(symbol));
    };
    bus.on('orderbook', onBook);
    // keep-alive ping
    const ping = setInterval(() => res.write(`:\n\n`), 15000);
    req.on('close', () => {
        clearInterval(ping);
        bus.off('orderbook', onBook);
        res.end();
    });
});
/** ME + Balances */
app.get('/v1/me', async (req, res) => {
    try {
        const user = await requireUser(req);
        const full = await prisma.user.findUnique({
            where: { id: user.id },
            include: { kyc: true, balances: true },
        });
        res.json({ ok: true, user: full });
    }
    catch (e) {
        res.status(400).json({ ok: false, error: String(e?.message ?? e) });
    }
});
app.get('/v1/balances', async (req, res) => {
    try {
        const user = await requireUser(req);
        const balances = await prisma.balance.findMany({ where: { userId: user.id } });
        res.json({ ok: true, balances });
    }
    catch (e) {
        res.status(400).json({ ok: false, error: String(e?.message ?? e) });
    }
});
/** My Orders / Trades */
app.get('/v1/my/orders', async (req, res) => {
    try {
        const user = await requireUser(req);
        const status = req.query.status;
        const where = { userId: user.id };
        if (status)
            where.status = status;
        const orders = await prisma.order.findMany({
            where,
            orderBy: { createdAt: 'desc' },
            take: 200,
        });
        res.json({ ok: true, orders });
    }
    catch (e) {
        res.status(400).json({ ok: false, error: String(e?.message ?? e) });
    }
});
app.get('/v1/my/trades', async (req, res) => {
    try {
        const user = await requireUser(req);
        const trades = await prisma.trade.findMany({
            where: {
                OR: [
                    { buyOrder: { userId: user.id } },
                    { sellOrder: { userId: user.id } },
                ],
            },
            orderBy: { createdAt: 'desc' },
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
app.post('/v1/faucet', async (req, res) => {
    try {
        const user = await requireUser(req);
        const { asset, amount } = req.body ?? {};
        if (!asset || !amount) {
            return res.status(400).json({ ok: false, error: 'asset & amount required' });
        }
        const amt = new library_1.Decimal(String(amount));
        await prisma.balance.upsert({
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
app.post('/v1/kyc/submit', async (req, res) => {
    try {
        const user = await requireUser(req);
        const { legalName, country, dob, docType, docHash } = req.body ?? {};
        if (!legalName || !country || !dob || !docType || !docHash) {
            return res.status(400).json({ ok: false, error: 'missing fields' });
        }
        const rec = await prisma.kyc.upsert({
            where: { userId: user.id },
            update: {
                legalName, country, dob: new Date(dob), docType, docHash,
                status: 'PENDING', updatedAt: new Date(),
            },
            create: {
                userId: user.id, legalName, country, dob: new Date(dob),
                docType, docHash, status: 'PENDING', riskScore: new library_1.Decimal(0),
            },
        });
        res.json({ ok: true, kyc: rec });
    }
    catch (e) {
        res.status(400).json({ ok: false, error: String(e?.message ?? e) });
    }
});
// ===== Market endpoints (v1) =====
const qOrderbook = zod_1.z.object({
    symbol: zod_1.z.string().min(1),
    depth: zod_1.z.coerce.number().int().min(1).max(200).default(10),
});
app.get("/api/v1/market/orderbook", async (req, res) => {
    try {
        const { symbol, depth } = qOrderbook.parse(req.query);
        const s = symbol.toUpperCase();
        const [bids, asks] = await Promise.all([
            prisma.order.findMany({
                where: { symbol: s, status: "OPEN", side: "BUY" },
                orderBy: [{ price: "desc" }, { createdAt: "asc" }],
                take: depth,
            }),
            prisma.order.findMany({
                where: { symbol: s, status: "OPEN", side: "SELL" },
                orderBy: [{ price: "asc" }, { createdAt: "asc" }],
                take: depth,
            }),
        ]);
        res.json({
            symbol: s,
            depth,
            bids: bids.map((o) => ({ price: o.price.toString(), qty: o.qty.toString() })),
            asks: asks.map((o) => ({ price: o.price.toString(), qty: o.qty.toString() })),
        });
    }
    catch (e) {
        res.status(400).json({ ok: false, error: String(e?.message ?? e) });
    }
});
const qTrades = zod_1.z.object({
    symbol: zod_1.z.string().min(1),
    limit: zod_1.z.coerce.number().int().min(1).max(200).default(25),
});
app.get("/api/v1/market/trades", async (req, res) => {
    try {
        const { symbol, limit } = qTrades.parse(req.query);
        const s = symbol.toUpperCase();
        const trades = await prisma.trade.findMany({
            where: { symbol: s },
            orderBy: { createdAt: "desc" },
            take: limit,
        });
        res.json({
            symbol: s,
            limit,
            trades: trades.map((t) => ({
                id: t.id.toString(),
                price: t.price.toString(),
                qty: t.qty.toString(),
                createdAt: t.createdAt,
            })),
        });
    }
    catch (e) {
        res.status(400).json({ ok: false, error: String(e?.message ?? e) });
    }
});
const qCandles = zod_1.z.object({
    symbol: zod_1.z.string().min(1),
    period: zod_1.z.enum(["24h", "7d", "30d"]).default("24h"),
});
app.get("/api/v1/market/candles", async (req, res) => {
    try {
        const { symbol, period } = qCandles.parse(req.query);
        const s = symbol.toUpperCase();
        const now = Date.now();
        const cfg = period === "24h"
            ? { ms: 24 * 60 * 60 * 1000, interval: 5 * 60 * 1000 }
            : period === "7d"
                ? { ms: 7 * 24 * 60 * 60 * 1000, interval: 60 * 60 * 1000 }
                : { ms: 30 * 24 * 60 * 60 * 1000, interval: 4 * 60 * 60 * 1000 };
        const start = new Date(now - cfg.ms);
        const trades = await prisma.trade.findMany({
            where: { symbol: s, createdAt: { gte: start } },
            orderBy: { createdAt: "asc" },
            take: 5000,
        });
        const candles = buildCandles(trades, now - cfg.ms, now, cfg.interval, s);
        res.json({
            symbol: s,
            period,
            intervalMs: cfg.interval,
            candles,
        });
    }
    catch (e) {
        res.status(400).json({ ok: false, error: String(e?.message ?? e) });
    }
});
function buildCandles(trades, startMs, endMs, intervalMs, seedKey) {
    // If no trades, generate deterministic synthetic candles (demo-safe)
    if (!trades.length)
        return syntheticCandles(startMs, endMs, intervalMs, seedKey);
    const buckets = new Map();
    for (const t of trades) {
        const ts = new Date(t.createdAt).getTime();
        const b = startMs + Math.floor((ts - startMs) / intervalMs) * intervalMs;
        if (b < startMs || b > endMs)
            continue;
        const price = Number(t.price);
        const qty = Number(t.qty);
        const c = buckets.get(b);
        if (!c) {
            buckets.set(b, { t: b, o: price, h: price, l: price, c: price, v: qty });
        }
        else {
            c.h = Math.max(c.h, price);
            c.l = Math.min(c.l, price);
            c.c = price;
            c.v += qty;
        }
    }
    // Fill missing buckets by carrying forward last close
    const out = [];
    const keys = [...buckets.keys()].sort((a, b) => a - b);
    let lastClose = buckets.get(keys[0])?.o ?? 100;
    for (let t = startMs; t <= endMs; t += intervalMs) {
        const c = buckets.get(t);
        if (c) {
            lastClose = c.c;
            out.push(c);
        }
        else {
            out.push({ t, o: lastClose, h: lastClose, l: lastClose, c: lastClose, v: 0 });
        }
    }
    return out;
}
function syntheticCandles(startMs, endMs, intervalMs, seedKey) {
    const seed = hashString(seedKey);
    const rnd = mulberry32(seed);
    const out = [];
    let last = 100 + (seed % 50);
    for (let t = startMs; t <= endMs; t += intervalMs) {
        const drift = (rnd() - 0.5) * 2; // [-1, 1]
        const o = last;
        const c = Math.max(1, o + drift);
        const h = Math.max(o, c) + rnd();
        const l = Math.min(o, c) - rnd();
        const v = Math.floor(rnd() * 1000);
        out.push({ t, o, h, l, c, v });
        last = c;
    }
    return out;
}
function hashString(s) {
    let h = 2166136261;
    for (let i = 0; i < s.length; i++) {
        h ^= s.charCodeAt(i);
        h = Math.imul(h, 16777619);
    }
    return h >>> 0;
}
function mulberry32(a) {
    return function () {
        let t = (a += 0x6d2b79f5);
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}
/** --------- helpers --------- */
async function getOrderbook(symbol) {
    const bids = await prisma.order.findMany({
        where: { symbol, side: 'BUY', status: 'OPEN' },
        orderBy: [{ price: 'desc' }, { createdAt: 'asc' }],
        take: 25,
    });
    const asks = await prisma.order.findMany({
        where: { symbol, side: 'SELL', status: 'OPEN' },
        orderBy: [{ price: 'asc' }, { createdAt: 'asc' }],
        take: 25,
    });
    return { bids, asks };
}
async function getRecentTrades(symbol) {
    return prisma.trade.findMany({
        where: { symbol },
        orderBy: { createdAt: 'desc' },
        take: 50,
    });
}
/** price-time-priority matching */
async function match(tx, order) {
    let remaining = new library_1.Decimal(order.qty);
    const limit = new library_1.Decimal(order.price);
    const isBuy = order.side === 'BUY';
    while (remaining.gt(0)) {
        const counter = await tx.order.findFirst({
            where: {
                symbol: order.symbol,
                status: 'OPEN',
                side: isBuy ? 'SELL' : 'BUY',
                price: isBuy ? { lte: limit } : { gte: limit },
            },
            orderBy: [{ price: isBuy ? 'asc' : 'desc' }, { createdAt: 'asc' }],
        });
        if (!counter)
            break;
        const tradeQty = library_1.Decimal.min(remaining, counter.qty);
        const tradePrice = counter.price; // fill at resting price
        await tx.trade.create({
            data: {
                symbol: order.symbol,
                price: tradePrice,
                qty: tradeQty,
                buyOrderId: isBuy ? order.id : counter.id,
                sellOrderId: isBuy ? counter.id : order.id,
            },
        });
        // notify listeners (candles, etc.)
        bus.emit('trade', order.symbol);
        // decrement counterparty
        const counterLeft = counter.qty.minus(tradeQty);
        await tx.order.update({
            where: { id: counter.id },
            data: counterLeft.lte(0)
                ? { status: 'FILLED', qty: new library_1.Decimal(0) }
                : { qty: counterLeft },
        });
        remaining = remaining.minus(tradeQty);
    }
    // update incoming order
    await tx.order.update({
        where: { id: order.id },
        data: remaining.lte(0)
            ? { status: 'FILLED', qty: new library_1.Decimal(0) }
            : { qty: remaining },
    });
}
/** start server */
app.listen(PORT, '0.0.0.0', () => {
    console.log(`api listening on :${PORT}`);
});
/** log unhandled errors */
process.on('unhandledRejection', (e) => console.error('unhandledRejection', e));
process.on('uncaughtException', (e) => console.error('uncaughtException', e));
