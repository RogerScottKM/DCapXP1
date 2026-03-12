"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.UIPlanSchema = exports.WidgetSchema = exports.IntentSchema = exports.PersonaSchema = void 0;
const zod_1 = require("zod");
/**
 * =========================================================
 * DCapX UI “DNA”
 * Agent outputs a JSON plan (validated here).
 * Renderer renders. Agent never outputs React code.
 * =========================================================
 */
exports.PersonaSchema = zod_1.z.enum(['Newbie', 'Scalper', 'Passive', 'Whale']);
exports.IntentSchema = zod_1.z.enum(['VIEW_MARKET', 'EXECUTE_TRADE', 'ONBOARDING']);
// --------- Widgets (v1: keep small, composable, safe) ---------
const SimpleChartSchema = zod_1.z.object({
    type: zod_1.z.literal('SimpleChart'),
    symbol: zod_1.z.string().min(1),
    color: zod_1.z.enum(['green', 'red', 'neutral']).default('neutral'),
    period: zod_1.z.enum(['24h', '7d']).default('24h')
});
const ProChartSchema = zod_1.z.object({
    type: zod_1.z.literal('ProChart'),
    symbol: zod_1.z.string().min(1),
    interval: zod_1.z.enum(['1m', '15m', '1h', '4h', '1d']).default('1h'),
    overlays: zod_1.z.array(zod_1.z.string()).optional()
});
const OrderBookSchema = zod_1.z.object({
    type: zod_1.z.literal('OrderBook'),
    symbol: zod_1.z.string().min(1),
    depth: zod_1.z.number().int().min(1).max(200).default(10)
});
const TradeHistorySchema = zod_1.z.object({
    type: zod_1.z.literal('TradeHistory'),
    symbol: zod_1.z.string().min(1),
    limit: zod_1.z.number().int().min(1).max(200).default(25)
});
const QuickOrderSchema = zod_1.z.object({
    type: zod_1.z.literal('QuickOrder'),
    symbol: zod_1.z.string().min(1),
    allowedTypes: zod_1.z.array(zod_1.z.enum(['MARKET', 'LIMIT', 'STOP_LOSS'])).min(1),
    defaultSide: zod_1.z.enum(['BUY', 'SELL']).default('BUY')
});
const RiskWarningSchema = zod_1.z.object({
    type: zod_1.z.literal('RiskWarning'),
    level: zod_1.z.enum(['INFO', 'WARNING', 'CRITICAL']).default('INFO'),
    message: zod_1.z.string().min(1),
    mustAcknowledge: zod_1.z.boolean().default(false)
});
const OnboardingSchema = zod_1.z.object({
    type: zod_1.z.literal('Onboarding'),
    currentStep: zod_1.z.number().int().min(1).default(1),
    totalSteps: zod_1.z.number().int().min(1).default(3),
    requiredDocs: zod_1.z.array(zod_1.z.string()).default([])
});
const PortfolioSummarySchema = zod_1.z.object({
    type: zod_1.z.literal('PortfolioSummary'),
    showSensitiveValues: zod_1.z.boolean().default(false)
});
// The complete union
exports.WidgetSchema = zod_1.z.discriminatedUnion('type', [
    SimpleChartSchema,
    ProChartSchema,
    OrderBookSchema,
    TradeHistorySchema,
    QuickOrderSchema,
    RiskWarningSchema,
    OnboardingSchema,
    PortfolioSummarySchema
]);
// --------- Plan schema ---------
exports.UIPlanSchema = zod_1.z.object({
    version: zod_1.z.literal('1.0'),
    generatedFor: zod_1.z.object({
        userId: zod_1.z.number().int().nonnegative(),
        persona: exports.PersonaSchema,
        intent: exports.IntentSchema
    }),
    layout: zod_1.z.array(zod_1.z.object({
        id: zod_1.z.string().min(1),
        colSpan: zod_1.z.union([zod_1.z.literal(1), zod_1.z.literal(2), zod_1.z.literal(3)]).default(3),
        priority: zod_1.z.number().int().min(1).default(1),
        widget: exports.WidgetSchema
    }))
});
