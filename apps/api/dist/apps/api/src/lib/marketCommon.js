"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parsePositiveInt = parsePositiveInt;
exports.parseLevel = parseLevel;
exports.aggregateByPrice = aggregateByPrice;
// apps/api/src/lib/marketCommon.ts
const library_1 = require("@prisma/client/runtime/library");
function parsePositiveInt(v, fallback, opts) {
    const min = opts?.min ?? 1;
    const max = opts?.max ?? 10_000;
    const n = Number(v);
    const x = Number.isFinite(n) ? Math.floor(n) : fallback;
    if (!Number.isFinite(x))
        return fallback;
    if (x < min)
        return min;
    if (x > max)
        return max;
    return x;
}
function parseLevel(v) {
    const s = String(v ?? "").trim();
    return s === "3" ? 3 : 2; // default L2
}
function aggregateByPrice(rows, depth) {
    // insertion order preserved; relies on DB sorting (price + time)
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
