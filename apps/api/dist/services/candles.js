"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CandleService = void 0;
// apps/api/src/services/candles.ts
const prisma_1 = require("../infra/prisma");
exports.CandleService = {
    async getCandles(symbol, period) {
        const now = Date.now();
        const cfg = period === "24h"
            ? { ms: 24 * 60 * 60 * 1000, interval: 5 * 60 * 1000 }
            : period === "7d"
                ? { ms: 7 * 24 * 60 * 60 * 1000, interval: 60 * 60 * 1000 }
                : { ms: 30 * 24 * 60 * 60 * 1000, interval: 4 * 60 * 60 * 1000 };
        const start = new Date(now - cfg.ms);
        const trades = await prisma_1.prisma.trade.findMany({
            where: { symbol, createdAt: { gte: start } },
            orderBy: { createdAt: "asc" },
            take: 5000,
        });
        const candles = buildCandles(trades, now - cfg.ms, now, cfg.interval, symbol);
        return {
            intervalMs: cfg.interval,
            candles,
        };
    },
};
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
