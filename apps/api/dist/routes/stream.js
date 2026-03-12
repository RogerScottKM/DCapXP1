"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
// apps/api/src/routes/stream.ts
const client_1 = require("@prisma/client");
const express_1 = __importDefault(require("express"));
const prisma_1 = require("../infra/prisma");
const bus_1 = require("../infra/bus");
const json_1 = require("../infra/json");
const symbolControl_1 = require("../infra/symbolControl");
const featureFlags_1 = require("../infra/featureFlags");
const adminKey_1 = require("../infra/adminKey");
const mode_1 = require("../infra/mode");
const marketShared_1 = require("./marketShared");
const router = express_1.default.Router();
async function getRecentTrades(symbol, mode, limit, sinceMs) {
    const where = { symbol, mode };
    if (sinceMs && Number.isFinite(sinceMs)) {
        where.createdAt = { gte: new Date(sinceMs) };
    }
    return prisma_1.prisma.trade.findMany({
        where,
        orderBy: { createdAt: "desc" },
        take: limit,
    });
}
async function getOrderbookL3(symbol, mode, depth) {
    const [bids, asks] = await Promise.all([
        prisma_1.prisma.order.findMany({
            where: { symbol, mode, side: "BUY", status: "OPEN" },
            orderBy: [{ price: "desc" }, { createdAt: "asc" }],
            take: depth,
        }),
        prisma_1.prisma.order.findMany({
            where: { symbol, mode, side: "SELL", status: "OPEN" },
            orderBy: [{ price: "asc" }, { createdAt: "asc" }],
            take: depth,
        }),
    ]);
    return { bids, asks };
}
async function getOrderbookL2(symbol, mode, depth) {
    const takeRaw = Math.min(Math.max(depth * 50, 200), 2000);
    const [bidOrders, askOrders] = await Promise.all([
        prisma_1.prisma.order.findMany({
            where: { symbol, mode, side: "BUY", status: "OPEN" },
            orderBy: [{ price: "desc" }, { createdAt: "asc" }],
            take: takeRaw,
        }),
        prisma_1.prisma.order.findMany({
            where: { symbol, mode, side: "SELL", status: "OPEN" },
            orderBy: [{ price: "asc" }, { createdAt: "asc" }],
            take: takeRaw,
        }),
    ]);
    return {
        bids: (0, marketShared_1.aggregateByPrice)(bidOrders, depth),
        asks: (0, marketShared_1.aggregateByPrice)(askOrders, depth),
    };
}
const asDec = (v) => v instanceof client_1.Prisma.Decimal ? v : new client_1.Prisma.Decimal(v ?? "0");
const floorTo = (tsMs, periodMs) => Math.floor(tsMs / periodMs) * periodMs;
function parsePeriodMs(raw, fallbackMs) {
    const s = String(raw ?? "").trim();
    if (!s)
        return fallbackMs;
    // allow numeric ms (e.g. "300000")
    if (/^\d+$/.test(s))
        return Math.max(1, Number(s));
    // allow 1m, 5m, 1h, 1d, etc.
    const m = s.match(/^(\d+)\s*([smhdw])$/i);
    if (!m)
        return fallbackMs;
    const n = Number(m[1]);
    const unit = m[2].toLowerCase();
    const mult = unit === "s" ? 1000 :
        unit === "m" ? 60_000 :
            unit === "h" ? 3_600_000 :
                unit === "d" ? 86_400_000 :
                    unit === "w" ? 604_800_000 :
                        1;
    return Math.max(1, n * mult);
}
function aggregateTradesToCandles(tradesAsc, periodMs) {
    const out = new Map();
    for (const tr of tradesAsc) {
        const t = floorTo(tr.createdAt.getTime(), periodMs);
        const px = asDec(tr.price);
        const q = asDec(tr.qty);
        const cur = out.get(t);
        if (!cur) {
            out.set(t, { t, o: px, h: px, l: px, c: px, v: q, n: 1 });
        }
        else {
            cur.c = px;
            if (px.cmp(cur.h) > 0)
                cur.h = px;
            if (px.cmp(cur.l) < 0)
                cur.l = px;
            cur.v = cur.v.add(q);
            cur.n += 1;
        }
    }
    return out;
}
function materializeAndFillGaps(buckets, startBucket, endBucket, periodMs, seedClose) {
    // establish a starting close for pre-first-bucket gaps
    let lastClose = seedClose;
    if (!lastClose) {
        // fallback: first real candle open (if any)
        const firstKey = [...buckets.keys()].sort((a, b) => a - b)[0];
        if (firstKey !== undefined)
            lastClose = buckets.get(firstKey).o;
    }
    if (!lastClose)
        return []; // no data at all
    const out = [];
    for (let t = startBucket; t <= endBucket; t += periodMs) {
        const b = buckets.get(t);
        if (b) {
            out.push({
                t: b.t,
                o: b.o.toString(),
                h: b.h.toString(),
                l: b.l.toString(),
                c: b.c.toString(),
                v: b.v.toString(),
                n: b.n,
            });
            lastClose = b.c;
        }
        else {
            const px = lastClose.toString();
            out.push({ t, o: px, h: px, l: px, c: px, v: "0", n: 0 });
        }
    }
    return out;
}
async function getGapFilledCandles(symbol, mode, periodMs, limit, nowMs = Date.now()) {
    const endBucket = floorTo(nowMs, periodMs);
    const startBucket = endBucket - (limit - 1) * periodMs;
    const startDate = new Date(startBucket);
    const endDateExclusive = new Date(endBucket + periodMs);
    const [seedTrade, trades] = await Promise.all([
        prisma_1.prisma.trade.findFirst({
            where: { symbol, mode, createdAt: { lt: startDate } },
            orderBy: { createdAt: "desc" },
        }),
        prisma_1.prisma.trade.findMany({
            where: {
                symbol,
                mode,
                createdAt: { gte: startDate, lt: endDateExclusive },
            },
            orderBy: { createdAt: "asc" },
            take: 20000, // safety cap; adjust if you want
        }),
    ]);
    const buckets = aggregateTradesToCandles(trades, periodMs);
    const seedClose = seedTrade ? asDec(seedTrade.price) : undefined;
    return materializeAndFillGaps(buckets, startBucket, endBucket, periodMs, seedClose);
}
/**
 * GET /v1/stream/:symbol?mode=PAPER|LIVE&level=2|3&depth=25
 * - mode defaults to PAPER (or x-mode header)
 * - level defaults to flags.streamDefaultLevel (usually 2)
 * - L3 is gated unless admin or flags.publicAllowL3=true
 * - SSE itself can be disabled publicly via flags.enableSSE=false (admin still allowed)
 */
router.get("/stream/:symbol", async (req, res) => {
    const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
    const mode = (0, mode_1.resolveMode)(req);
    const depth = (0, marketShared_1.parsePositiveInt)(req.query.depth, 25, { min: 1, max: 500 });
    const tradesLimit = (0, marketShared_1.parsePositiveInt)(req.query.limit, 50, { min: 1, max: 20000 });
    const sinceMsRaw = req.query.sinceMs;
    const sinceMs = sinceMsRaw ? Number(sinceMsRaw) : undefined;
    // ---- candles over SSE (optional) ----
    const candlesEnabled = ["1", "true", "yes", "on"].includes(String(req.query.candles ?? "").toLowerCase());
    // reuse `period=` like /candles route (or allow candlePeriod=)
    const candlePeriodMs = parsePeriodMs(req.query.period ?? req.query.candlePeriod, 5 * 60_000);
    const candleLimit = (0, marketShared_1.parsePositiveInt)(req.query.candleLimit, 300, {
        min: 1,
        max: 5000,
    });
    const getCandles = async () => candlesEnabled
        ? await getGapFilledCandles(symbol, mode, candlePeriodMs, candleLimit)
        : undefined;
    let flags = featureFlags_1.featureFlags.get(symbol);
    // If SSE disabled publicly, still allow admin
    if (!flags.enableSSE && !(0, adminKey_1.isAdmin)(req)) {
        return res.status(503).json({
            ok: false,
            symbol,
            mode,
            code: "SSE_DISABLED",
            error: "SSE is currently disabled.",
            flags: {
                enableSSE: flags.enableSSE,
                streamDefaultLevel: flags.streamDefaultLevel,
                publicAllowL3: flags.publicAllowL3,
                orderbookDefaultLevel: flags.orderbookDefaultLevel,
            },
        });
    }
    // default level if not provided
    const requested = req.query.level;
    const level = requested === undefined || requested === null || String(requested).trim() === ""
        ? flags.streamDefaultLevel
        : (0, marketShared_1.parseBookLevel)(requested, flags.streamDefaultLevel);
    // L3 gating
    if (level === 3 && !(0, adminKey_1.isAdmin)(req) && !flags.publicAllowL3) {
        return res.status(403).json({
            ok: false,
            symbol,
            mode,
            code: "L3_DISABLED",
            error: "L3 stream is disabled for public requests. Provide x-admin-key or enable publicAllowL3.",
            flags: {
                publicAllowL3: flags.publicAllowL3,
                streamDefaultLevel: flags.streamDefaultLevel,
                orderbookDefaultLevel: flags.orderbookDefaultLevel,
            },
        });
    }
    res.setHeader("Content-Type", "text/event-stream");
    res.setHeader("Cache-Control", "no-cache");
    res.setHeader("Connection", "keep-alive");
    res.flushHeaders?.();
    const send = (event, data) => {
        res.write(`event: ${event}\n`);
        res.write(`data: ${(0, json_1.safeStringify)(data)}\n\n`);
    };
    const getBook = async () => level === 3
        ? await getOrderbookL3(symbol, mode, depth)
        : await getOrderbookL2(symbol, mode, depth);
    const shutdown = () => {
        clearInterval(ping);
        bus_1.bus.off("trade", onTrade);
        bus_1.bus.off("orderbook", onBook);
        bus_1.bus.off("symbolMode", onMode);
        bus_1.bus.off("flags", onFlags);
        res.end();
    };
    const onTrade = async (p) => {
        if (p.symbol === symbol && p.mode === mode) {
            const pushLimit = Math.min(tradesLimit, 200); // keep it sane
            const [trades, candles] = await Promise.all([
                getRecentTrades(symbol, mode, pushLimit, sinceMs),
                candlesEnabled ? getCandles() : Promise.resolve(undefined),
            ]);
            send("trades", { symbol, mode, trades });
            if (candlesEnabled) {
                send("candles", {
                    symbol,
                    mode,
                    periodMs: candlePeriodMs,
                    candles,
                });
            }
        }
    };
    const onBook = async (p) => {
        if (p.symbol === symbol && p.mode === mode) {
            send("orderbook", {
                symbol,
                mode,
                level,
                depth,
                control: symbolControl_1.symbolControl.get(symbol),
                orderbook: await getBook(),
            });
        }
    };
    const onMode = async (p) => {
        if (p.symbol === symbol) {
            send("mode", { symbol, control: symbolControl_1.symbolControl.get(symbol) });
            send("orderbook", { symbol, mode, level, depth, control: symbolControl_1.symbolControl.get(symbol), orderbook: await getBook() });
        }
    };
    const onFlags = async (p) => {
        if (p.symbol !== "*" && p.symbol !== symbol)
            return;
        flags = featureFlags_1.featureFlags.get(symbol);
        send("flags", { symbol, mode, flags });
        // If public SSE got disabled while connected (and user is not admin), terminate stream
        if (!flags.enableSSE && !(0, adminKey_1.isAdmin)(req)) {
            send("error", {
                ok: false,
                symbol,
                mode,
                code: "SSE_DISABLED",
                error: "SSE was disabled.",
                flags,
            });
            shutdown();
            return;
        }
        // If public L3 got disabled and this connection is L3 (and user is not admin), terminate
        if (level === 3 && !(0, adminKey_1.isAdmin)(req) && !flags.publicAllowL3) {
            send("error", {
                ok: false,
                symbol,
                mode,
                code: "L3_DISABLED",
                error: "L3 was disabled.",
                flags,
            });
            shutdown();
            return;
        }
    };
    bus_1.bus.on("trade", onTrade);
    bus_1.bus.on("orderbook", onBook);
    bus_1.bus.on("symbolMode", onMode);
    bus_1.bus.on("flags", onFlags);
    // initial snapshot
    try {
        send("snapshot", {
            symbol,
            mode,
            level,
            depth,
            control: symbolControl_1.symbolControl.get(symbol),
            candles: candlesEnabled ? await getCandles() : undefined,
            candleSpec: candlesEnabled ? { periodMs: candlePeriodMs, limit: candleLimit } : undefined,
            orderbook: await getBook(),
            trades: await getRecentTrades(symbol, mode, tradesLimit, sinceMs),
            flags: {
                enableSSE: flags.enableSSE,
                publicAllowL3: flags.publicAllowL3,
                streamDefaultLevel: flags.streamDefaultLevel,
                orderbookDefaultLevel: flags.orderbookDefaultLevel,
            },
        });
    }
    catch (e) {
        send("error", { ok: false, error: String(e?.message ?? e) });
    }
    // keep-alive ping
    const ping = setInterval(() => res.write(`:\n\n`), 15000);
    req.on("close", () => shutdown());
});
exports.default = router;
