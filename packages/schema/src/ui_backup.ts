import { z } from 'zod';

/**
 * =========================================================
 * DCapX UI “DNA”
 * Agent outputs a JSON plan (validated here).
 * Renderer renders. Agent never outputs React code.
 * =========================================================
 */

export const PersonaSchema = z.enum(['Newbie', 'Scalper', 'Passive', 'Whale']);
export type Persona = z.infer<typeof PersonaSchema>;

export const IntentSchema = z.enum(['VIEW_MARKET', 'EXECUTE_TRADE', 'ONBOARDING']);
export type Intent = z.infer<typeof IntentSchema>;

// --------- Widgets (v1: keep small, composable, safe) ---------

const SimpleChartSchema = z.object({
  type: z.literal('SimpleChart'),
  symbol: z.string().min(1),
  color: z.enum(['green', 'red', 'neutral']).default('neutral'),
  period: z.enum(['24h', '7d']).default('24h')
});

const ProChartSchema = z.object({
  type: z.literal('ProChart'),
  symbol: z.string().min(1),
  interval: z.enum(['1m', '15m', '1h', '4h', '1d']).default('1h'),
  overlays: z.array(z.string()).optional()
});

const OrderBookSchema = z.object({
  type: z.literal('OrderBook'),
  symbol: z.string().min(1),
  depth: z.number().int().min(1).max(200).default(10)
});

const TradeHistorySchema = z.object({
  type: z.literal('TradeHistory'),
  symbol: z.string().min(1),
  limit: z.number().int().min(1).max(200).default(25)
});

const QuickOrderSchema = z.object({
  type: z.literal('QuickOrder'),
  symbol: z.string().min(1),
  allowedTypes: z.array(z.enum(['MARKET', 'LIMIT', 'STOP_LOSS'])).min(1),
  defaultSide: z.enum(['BUY', 'SELL']).default('BUY')
});

const RiskWarningSchema = z.object({
  type: z.literal('RiskWarning'),
  level: z.enum(['INFO', 'WARNING', 'CRITICAL']).default('INFO'),
  message: z.string().min(1),
  mustAcknowledge: z.boolean().default(false)
});

const OnboardingSchema = z.object({
  type: z.literal('Onboarding'),
  currentStep: z.number().int().min(1).default(1),
  totalSteps: z.number().int().min(1).default(3),
  requiredDocs: z.array(z.string()).default([])
});

const PortfolioSummarySchema = z.object({
  type: z.literal('PortfolioSummary'),
  showSensitiveValues: z.boolean().default(false)
});

// The complete union
export const WidgetSchema = z.discriminatedUnion('type', [
  SimpleChartSchema,
  ProChartSchema,
  OrderBookSchema,
  TradeHistorySchema,
  QuickOrderSchema,
  RiskWarningSchema,
  OnboardingSchema,
  PortfolioSummarySchema
]);

export type WidgetProps = z.infer<typeof WidgetSchema>;

// --------- Plan schema ---------

export const UIPlanSchema = z.object({
  version: z.literal('1.0'),
  generatedFor: z.object({
    userId: z.number().int().nonnegative(),
    persona: PersonaSchema,
    intent: IntentSchema
  }),
  layout: z.array(
    z.object({
      id: z.string().min(1),
      colSpan: z.union([z.literal(1), z.literal(2), z.literal(3)]).default(3),
      priority: z.number().int().min(1).default(1),
      widget: WidgetSchema
    })
  )
});

export type UIPlan = z.infer<typeof UIPlanSchema>;
