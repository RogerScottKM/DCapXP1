import { z } from "zod";

/**
 * =========================================================
 * DCapX UI “DNA”
 * Agent outputs a JSON plan (validated here).
 * Renderer renders. Agent never outputs React code.
 * =========================================================
 */

export const PersonaSchema = z.enum(["Newbie", "Scalper", "Passive", "Whale"]);
export type Persona = z.infer<typeof PersonaSchema>;

export const IntentSchema = z.enum(["VIEW_MARKET", "EXECUTE_TRADE", "ONBOARDING"]);
export type Intent = z.infer<typeof IntentSchema>;

// A “safe” symbol shape (structure validation). Semantics allowlist happens in policy layer.
export const SymbolSchema = z
  .string()
  .min(1)
  .max(32)
  .regex(/^[A-Z0-9]{2,12}[-/][A-Z0-9]{2,12}$/, "Invalid symbol format (e.g. BTC-USD)");

export const UIPlanRequestSchema = z.object({
  userId: z.coerce.number().int().positive(),
  intent: IntentSchema.default("VIEW_MARKET"),
  symbol: SymbolSchema.default("BTC-USD"),
});
export type UIPlanRequest = z.infer<typeof UIPlanRequestSchema>;

// --------- Widgets ---------
const SimpleChartSchema = z.object({
  type: z.literal("SimpleChart"),
  symbol: SymbolSchema,
  color: z.enum(["green", "red", "neutral"]).default("neutral"),
  period: z.enum(["24h", "7d"]).default("24h"),
});

const ProChartSchema = z.object({
  type: z.literal("ProChart"),
  symbol: SymbolSchema,
  interval: z.enum(["1m", "15m", "1h", "4h", "1d"]).default("1h"),
  overlays: z.array(z.string()).optional(),
});

const OrderBookSchema = z.object({
  type: z.literal("OrderBook"),
  symbol: SymbolSchema,
  depth: z.number().int().min(1).max(200).default(10),
});

const TradeHistorySchema = z.object({
  type: z.literal("TradeHistory"),
  symbol: SymbolSchema,
  limit: z.number().int().min(1).max(200).default(25),
});

const QuickOrderSchema = z.object({
  type: z.literal("QuickOrder"),
  symbol: SymbolSchema,
  allowedTypes: z.array(z.enum(["MARKET", "LIMIT", "STOP_LOSS"])).min(1),
  defaultSide: z.enum(["BUY", "SELL"]).default("BUY"),
});

const RiskWarningSchema = z.object({
  type: z.literal("RiskWarning"),
  level: z.enum(["INFO", "WARNING", "CRITICAL"]).default("INFO"),
  message: z.string().min(1),
  mustAcknowledge: z.boolean().default(false),
});

const OnboardingSchema = z.object({
  type: z.literal("Onboarding"),
  currentStep: z.number().int().min(1).default(1),
  totalSteps: z.number().int().min(1).default(3),
  requiredDocs: z.array(z.string()).default([]),
});

const PortfolioSummarySchema = z.object({
  type: z.literal("PortfolioSummary"),
  showSensitiveValues: z.boolean().default(false),
});

// New: generic error/fallback widget (for invalid symbol, provider errors, etc.)
const ErrorStateSchema = z.object({
  type: z.literal("ErrorState"),
  title: z.string().default("Something went wrong"),
  message: z.string().min(1),
  recoverable: z.boolean().default(true),
});

export const WidgetSchema = z.discriminatedUnion("type", [
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
export type Widget = z.infer<typeof WidgetSchema>;
// Backwards-compatible alias (your web expects this name)
export type WidgetProps = Widget;

export const LayoutItemSchema = z.object({
  id: z.string().min(1),
  colSpan: z.union([z.literal(1), z.literal(2), z.literal(3)]).default(3),
  priority: z.number().int().min(1).default(1),
  widget: WidgetSchema,
});
export type LayoutItem = z.infer<typeof LayoutItemSchema>;

export const UIPlanSchema = z.object({
  version: z.literal("1.0"),
  generatedFor: z.object({
    userId: z.number().int().positive(),
    persona: PersonaSchema,
    intent: IntentSchema,
    symbol: SymbolSchema,
  }),
  layout: z.array(LayoutItemSchema),
});
export type UIPlan = z.infer<typeof UIPlanSchema>;
