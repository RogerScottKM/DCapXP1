"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.riskLimits = void 0;
// apps/api/src/infra/riskLimits.ts
const library_1 = require("@prisma/client/runtime/library");
function normalizeSymbol(sym) {
    return String(sym ?? "").toUpperCase().trim();
}
function toDecimalString(v) {
    if (v === undefined || v === null)
        return undefined;
    const s = String(v).trim();
    if (!s)
        return undefined;
    // Validate it parses as Decimal and is >= 0
    const d = new library_1.Decimal(s);
    if (d.isNaN() || d.isNeg())
        return undefined;
    return d.toString();
}
class RiskLimitsStore {
    defaults = {
        // sensible demo defaults (tune anytime)
        maxOrderQty: "1000000",
        maxOrderNotional: "1000000000",
        maxOpenOrders: 1000,
        updatedAt: new Date().toISOString(),
        updatedBy: "system",
        reason: "defaults",
    };
    overrides = new Map(); // per symbol
    get(symbol) {
        const s = normalizeSymbol(symbol);
        const ov = this.overrides.get(s);
        if (!ov)
            return { ...this.defaults };
        return {
            ...this.defaults,
            ...ov,
        };
    }
    getDefaults() {
        return { ...this.defaults };
    }
    listOverrides() {
        const out = [];
        for (const [symbol, state] of this.overrides.entries())
            out.push({ symbol, ...state });
        return out;
    }
    setDefaults(next) {
        const updated = {
            ...this.defaults,
            maxOrderQty: next.maxOrderQty !== undefined ? toDecimalString(next.maxOrderQty) : this.defaults.maxOrderQty,
            maxOrderNotional: next.maxOrderNotional !== undefined ? toDecimalString(next.maxOrderNotional) : this.defaults.maxOrderNotional,
            maxOpenOrders: next.maxOpenOrders !== undefined ? next.maxOpenOrders : this.defaults.maxOpenOrders,
            reason: next.reason ?? this.defaults.reason,
            updatedBy: next.updatedBy ?? "admin",
            updatedAt: new Date().toISOString(),
        };
        this.defaults = updated;
        return { ...this.defaults };
    }
    set(symbol, next) {
        const s = normalizeSymbol(symbol);
        const prev = this.overrides.get(s);
        const base = prev ?? { ...this.defaults };
        const updated = {
            ...base,
            maxOrderQty: next.maxOrderQty !== undefined ? toDecimalString(next.maxOrderQty) : base.maxOrderQty,
            maxOrderNotional: next.maxOrderNotional !== undefined ? toDecimalString(next.maxOrderNotional) : base.maxOrderNotional,
            maxOpenOrders: next.maxOpenOrders !== undefined ? next.maxOpenOrders : base.maxOpenOrders,
            reason: next.reason ?? base.reason,
            updatedBy: next.updatedBy ?? "admin",
            updatedAt: new Date().toISOString(),
        };
        this.overrides.set(s, updated);
        return { ...updated };
    }
    clear(symbol) {
        const s = normalizeSymbol(symbol);
        this.overrides.delete(s);
    }
}
exports.riskLimits = new RiskLimitsStore();
