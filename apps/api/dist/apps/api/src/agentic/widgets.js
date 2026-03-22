"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.widgetCandidates = void 0;
const policy_1 = require("./policy");
exports.widgetCandidates = [
    {
        id: "risk",
        priority: 1,
        colSpan: 3,
        when: (ctx) => (0, policy_1.policyFor)(ctx).showRiskBanner,
        build: (ctx) => ({
            type: "RiskWarning",
            level: ctx.persona === "Newbie" ? "WARNING" : "INFO",
            message: "Dynamic plan: persona + policy are live. Next: real market data + workflows.",
            mustAcknowledge: ctx.persona === "Newbie",
        }),
    },
    // If symbol is disallowed, render safe-mode error + basic chart only
    {
        id: "symbol_error",
        priority: 2,
        colSpan: 3,
        when: (ctx) => !(0, policy_1.policyFor)(ctx).symbolAllowed,
        build: (ctx) => ({
            type: "ErrorState",
            title: "Unsupported symbol",
            message: `Symbol '${ctx.symbol}' is not allowed in this environment yet.`,
            recoverable: true,
        }),
    },
    {
        id: "chart",
        priority: 3,
        colSpan: 3,
        build: (ctx) => ({
            type: ctx.persona === "Scalper" || ctx.persona === "Whale" ? "ProChart" : "SimpleChart",
            symbol: ctx.symbol,
            ...(ctx.persona === "Scalper" || ctx.persona === "Whale"
                ? { interval: "1m", overlays: ["VWAP", "RSI"] }
                : { period: "24h", color: "neutral" }),
        }),
    },
    {
        id: "ob",
        priority: 4,
        colSpan: 2,
        when: (ctx) => (0, policy_1.policyFor)(ctx).symbolAllowed,
        build: (ctx) => ({
            type: "OrderBook",
            symbol: ctx.symbol,
            depth: 10,
        }),
    },
    {
        id: "qo",
        priority: 4,
        colSpan: 1,
        when: (ctx) => (0, policy_1.policyFor)(ctx).symbolAllowed && (0, policy_1.policyFor)(ctx).allowOrderEntry,
        build: (ctx) => ({
            type: "QuickOrder",
            symbol: ctx.symbol,
            allowedTypes: [...(0, policy_1.policyFor)(ctx).allowedOrderTypes],
            defaultSide: "BUY",
        }),
    },
    {
        id: "trades",
        priority: 5,
        colSpan: 3,
        when: (ctx) => (0, policy_1.policyFor)(ctx).symbolAllowed,
        build: (ctx) => ({
            type: "TradeHistory",
            symbol: ctx.symbol,
            limit: 25,
        }),
    },
];
