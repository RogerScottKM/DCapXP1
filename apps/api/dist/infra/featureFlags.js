"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.featureFlags = void 0;
function envBool(name, fallback) {
    const v = process.env[name];
    if (v === undefined)
        return fallback;
    return ["1", "true", "yes", "y", "on"].includes(String(v).toLowerCase());
}
function envLevel(name, fallback) {
    const v = String(process.env[name] ?? "").trim();
    if (v === "3")
        return 3;
    if (v === "2")
        return 2;
    return fallback;
}
function nowIso() {
    return new Date().toISOString();
}
const defaults = {
    orderbookDefaultLevel: envLevel("ORDERBOOK_DEFAULT_LEVEL", 2),
    streamDefaultLevel: envLevel("STREAM_DEFAULT_LEVEL", 2),
    publicAllowL3: envBool("PUBLIC_ALLOW_L3", false),
    enableSSE: envBool("ENABLE_SSE", true),
    updatedAt: nowIso(),
    updatedBy: "boot",
    reason: "env defaults",
};
const perSymbol = new Map();
function merge(base, patch) {
    return {
        ...base,
        ...patch,
        updatedAt: nowIso(),
        updatedBy: patch.updatedBy ?? base.updatedBy,
        reason: patch.reason ?? base.reason,
    };
}
exports.featureFlags = {
    getDefaults() {
        return { ...defaults };
    },
    setDefaults(patch) {
        const next = merge(defaults, patch);
        Object.assign(defaults, next);
        return { ...defaults };
    },
    get(symbol) {
        if (!symbol)
            return { ...defaults };
        const key = symbol.toUpperCase();
        const cur = perSymbol.get(key);
        return cur ? { ...cur } : { ...defaults };
    },
    set(symbol, patch) {
        const key = symbol.toUpperCase();
        const base = perSymbol.get(key) ?? { ...defaults };
        const next = merge(base, patch);
        perSymbol.set(key, next);
        return { ...next };
    },
    clear(symbol) {
        perSymbol.delete(symbol.toUpperCase());
    },
    listOverrides() {
        return Array.from(perSymbol.entries()).map(([symbol, flags]) => ({
            symbol,
            flags: { ...flags },
        }));
    },
};
