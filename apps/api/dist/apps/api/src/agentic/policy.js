"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.policyFor = policyFor;
const SAFE_SYMBOLS = new Set(["BTC-USD", "ETH-USD", "SOL-USD"]); // v0 allowlist
function policyFor(ctx) {
    const isNewbie = ctx.persona === "Newbie";
    const isWhale = ctx.persona === "Whale";
    return {
        // Semantics validation lives here (not Zod):
        symbolAllowed: SAFE_SYMBOLS.has(ctx.symbol),
        showRiskBanner: true,
        allowOrderEntry: true, // keep on for demo
        allowedOrderTypes: isNewbie
            ? ["MARKET", "LIMIT"]
            : ["MARKET", "LIMIT", "STOP_LOSS"],
        // placeholder for later leverage/margin policy
        allowLeverage: isWhale,
    };
}
