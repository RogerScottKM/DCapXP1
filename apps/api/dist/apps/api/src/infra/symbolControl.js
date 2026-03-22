"use strict";
// apps/api/src/infra/symbolControl.ts
Object.defineProperty(exports, "__esModule", { value: true });
exports.symbolControl = void 0;
exports.isNewOrderAllowed = isNewOrderAllowed;
exports.explainMode = explainMode;
function normalizeSymbol(sym) {
    return String(sym ?? "").toUpperCase().trim();
}
class SymbolControlStore {
    m = new Map();
    get(symbol) {
        const s = normalizeSymbol(symbol);
        const cur = this.m.get(s);
        if (cur)
            return cur;
        return { mode: "OPEN", updatedAt: new Date().toISOString(), updatedBy: "system" };
    }
    set(symbol, next) {
        const s = normalizeSymbol(symbol);
        const state = {
            mode: next.mode,
            reason: next.reason,
            updatedBy: next.updatedBy ?? "admin",
            updatedAt: new Date().toISOString(),
        };
        this.m.set(s, state);
        return state;
    }
    clear(symbol) {
        const s = normalizeSymbol(symbol);
        this.m.delete(s);
    }
    list() {
        const out = [];
        for (const [symbol, state] of this.m.entries())
            out.push({ symbol, ...state });
        return out;
    }
}
exports.symbolControl = new SymbolControlStore();
function isNewOrderAllowed(mode) {
    return mode === "OPEN";
}
function explainMode(mode) {
    if (mode === "HALT")
        return "Trading HALTED: no new orders (cancels allowed).";
    if (mode === "CANCEL_ONLY")
        return "CANCEL_ONLY: no new orders (cancels allowed).";
    return "OPEN";
}
