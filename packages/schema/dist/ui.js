"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.UIPlanSchema = exports.LayoutItemSchema = exports.WidgetSchema = exports.UIPlanRequestSchema = exports.SymbolSchema = exports.IntentSchema = exports.PersonaSchema = void 0;
const zod_1 = require("zod");
/**
 * =========================================================
 * DCapX UI “DNA”
 * Agent outputs a JSON plan (validated here).
 * Renderer renders. Agent never outputs React code.
 * =========================================================
 */
exports.PersonaSchema = zod_1.z.enum(["Newbie", "Scalper", "Passive", "Whale"]);
exports.IntentSchema = zod_1.z.enum(["VIEW_MARKET", "EXECUTE_TRADE", "ONBOARDING"]);
// A “safe” symbol shape (structure validation). Semantics allowlist happens in policy layer.
exports.SymbolSchema = zod_1.z
    .string()
    .min(1)
    .max(32)
    .regex(/^[A-Z0-9]{2,12}[-/][A-Z0-9]{2,12}$/, "Invalid symbol format (e.g. BTC-USD)");
exports.UIPlanRequestSchema = zod_1.z.object({
    userId: zod_1.z.coerce.number().int().positive(),
    intent: exports.IntentSchema.default("VIEW_MARKET"),
    symbol: exports.SymbolSchema.default("BTC-USD"),
});
// --------- Widgets ---------
const SimpleChartSchema = zod_1.z.object({
    type: zod_1.z.literal("SimpleChart"),
    symbol: exports.SymbolSchema,
    color: zod_1.z.enum(["green", "red", "neutral"]).default("neutral"),
    period: zod_1.z.enum(["24h", "7d"]).default("24h"),
});
const ProChartSchema = zod_1.z.object({
    type: zod_1.z.literal("ProChart"),
    symbol: exports.SymbolSchema,
    interval: zod_1.z.enum(["1m", "15m", "1h", "4h", "1d"]).default("1h"),
    overlays: zod_1.z.array(zod_1.z.string()).optional(),
});
const OrderBookSchema = zod_1.z.object({
    type: zod_1.z.literal("OrderBook"),
    symbol: exports.SymbolSchema,
    depth: zod_1.z.number().int().min(1).max(200).default(10),
});
const TradeHistorySchema = zod_1.z.object({
    type: zod_1.z.literal("TradeHistory"),
    symbol: exports.SymbolSchema,
    limit: zod_1.z.number().int().min(1).max(200).default(25),
});
const QuickOrderSchema = zod_1.z.object({
    type: zod_1.z.literal("QuickOrder"),
    symbol: exports.SymbolSchema,
    allowedTypes: zod_1.z.array(zod_1.z.enum(["MARKET", "LIMIT", "STOP_LOSS"])).min(1),
    defaultSide: zod_1.z.enum(["BUY", "SELL"]).default("BUY"),
});
const RiskWarningSchema = zod_1.z.object({
    type: zod_1.z.literal("RiskWarning"),
    level: zod_1.z.enum(["INFO", "WARNING", "CRITICAL"]).default("INFO"),
    message: zod_1.z.string().min(1),
    mustAcknowledge: zod_1.z.boolean().default(false),
});
const OnboardingSchema = zod_1.z.object({
    type: zod_1.z.literal("Onboarding"),
    currentStep: zod_1.z.number().int().min(1).default(1),
    totalSteps: zod_1.z.number().int().min(1).default(3),
    requiredDocs: zod_1.z.array(zod_1.z.string()).default([]),
});
const PortfolioSummarySchema = zod_1.z.object({
    type: zod_1.z.literal("PortfolioSummary"),
    showSensitiveValues: zod_1.z.boolean().default(false),
});
// New: generic error/fallback widget (for invalid symbol, provider errors, etc.)
const ErrorStateSchema = zod_1.z.object({
    type: zod_1.z.literal("ErrorState"),
    title: zod_1.z.string().default("Something went wrong"),
    message: zod_1.z.string().min(1),
    recoverable: zod_1.z.boolean().default(true),
});
exports.WidgetSchema = zod_1.z.discriminatedUnion("type", [
    SimpleChartSchema,
    ProChartSchema,
    OrderBookSchema,
    TradeHistorySchema,
    QuickOrderSchema,
    RiskWarningSchema,
    OnboardingSchema,
    PortfolioSummarySchema,
    ErrorStateSchema,
]);
exports.LayoutItemSchema = zod_1.z.object({
    id: zod_1.z.string().min(1),
    colSpan: zod_1.z.union([zod_1.z.literal(1), zod_1.z.literal(2), zod_1.z.literal(3)]).default(3),
    priority: zod_1.z.number().int().min(1).default(1),
    widget: exports.WidgetSchema,
});
exports.UIPlanSchema = zod_1.z.object({
    version: zod_1.z.literal("1.0"),
    generatedFor: zod_1.z.object({
        userId: zod_1.z.number().int().positive(),
        persona: exports.PersonaSchema,
        intent: exports.IntentSchema,
        symbol: exports.SymbolSchema,
    }),
    layout: zod_1.z.array(exports.LayoutItemSchema),
});
