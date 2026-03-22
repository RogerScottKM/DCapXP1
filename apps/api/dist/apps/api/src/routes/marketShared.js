"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parsePositiveInt = parsePositiveInt;
exports.parseBookLevel = parseBookLevel;
exports.aggregateByPrice = aggregateByPrice;
// apps/api/src/routes/marketShared.ts
const library_1 = require("@prisma/client/runtime/library");
function parsePositiveInt(v, fallback, opts = {}) {
    const min = opts.min ?? 1;
    const max = opts.max ?? 10_000;
    const n = Number(v);
    if (!Number.isFinite(n))
        return fallback;
    const x = Math.floor(n);
    if (x < min)
        return min;
    if (x > max)
        return max;
    return x;
}
function parseBookLevel(v, fallback = 2) {
    const s = String(v ?? "").trim();
    if (s === "2")
        return 2;
    if (s === "3")
        return 3;
    return fallback;
}
/**
 * Aggregates sorted L3 rows into L2 price buckets.
 * Assumes `rows` is already sorted best->worst (bids desc, asks asc).
 * Map preserves insertion order so level ordering stays correct.
 */
function aggregateByPrice(rows, depth) {
    const m = new Map();
    for (const r of rows) {
        const p = r.price?.toString?.() ?? String(r.price);
        const q = new library_1.Decimal(r.qty?.toString?.() ?? String(r.qty));
        const cur = m.get(p);
        m.set(p, cur ? cur.add(q) : q);
    }
    const out = [];
    for (const [price, qty] of m.entries()) {
        out.push({ price, qty: qty.toString() });
        if (out.length >= depth)
            break;
    }
    return out;
}
