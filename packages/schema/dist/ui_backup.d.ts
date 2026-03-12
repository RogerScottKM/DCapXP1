import { z } from 'zod';
/**
 * =========================================================
 * DCapX UI “DNA”
 * Agent outputs a JSON plan (validated here).
 * Renderer renders. Agent never outputs React code.
 * =========================================================
 */
export declare const PersonaSchema: z.ZodEnum<{
    Newbie: "Newbie";
    Scalper: "Scalper";
    Passive: "Passive";
    Whale: "Whale";
}>;
export type Persona = z.infer<typeof PersonaSchema>;
export declare const IntentSchema: z.ZodEnum<{
    VIEW_MARKET: "VIEW_MARKET";
    EXECUTE_TRADE: "EXECUTE_TRADE";
    ONBOARDING: "ONBOARDING";
}>;
export type Intent = z.infer<typeof IntentSchema>;
export declare const WidgetSchema: z.ZodDiscriminatedUnion<[z.ZodObject<{
    type: z.ZodLiteral<"SimpleChart">;
    symbol: z.ZodString;
    color: z.ZodDefault<z.ZodEnum<{
        green: "green";
        red: "red";
        neutral: "neutral";
    }>>;
    period: z.ZodDefault<z.ZodEnum<{
        "24h": "24h";
        "7d": "7d";
    }>>;
}, z.core.$strip>, z.ZodObject<{
    type: z.ZodLiteral<"ProChart">;
    symbol: z.ZodString;
    interval: z.ZodDefault<z.ZodEnum<{
        "1m": "1m";
        "15m": "15m";
        "1h": "1h";
        "4h": "4h";
        "1d": "1d";
    }>>;
    overlays: z.ZodOptional<z.ZodArray<z.ZodString>>;
}, z.core.$strip>, z.ZodObject<{
    type: z.ZodLiteral<"OrderBook">;
    symbol: z.ZodString;
    depth: z.ZodDefault<z.ZodNumber>;
}, z.core.$strip>, z.ZodObject<{
    type: z.ZodLiteral<"TradeHistory">;
    symbol: z.ZodString;
    limit: z.ZodDefault<z.ZodNumber>;
}, z.core.$strip>, z.ZodObject<{
    type: z.ZodLiteral<"QuickOrder">;
    symbol: z.ZodString;
    allowedTypes: z.ZodArray<z.ZodEnum<{
        MARKET: "MARKET";
        LIMIT: "LIMIT";
        STOP_LOSS: "STOP_LOSS";
    }>>;
    defaultSide: z.ZodDefault<z.ZodEnum<{
        BUY: "BUY";
        SELL: "SELL";
    }>>;
}, z.core.$strip>, z.ZodObject<{
    type: z.ZodLiteral<"RiskWarning">;
    level: z.ZodDefault<z.ZodEnum<{
        INFO: "INFO";
        WARNING: "WARNING";
        CRITICAL: "CRITICAL";
    }>>;
    message: z.ZodString;
    mustAcknowledge: z.ZodDefault<z.ZodBoolean>;
}, z.core.$strip>, z.ZodObject<{
    type: z.ZodLiteral<"Onboarding">;
    currentStep: z.ZodDefault<z.ZodNumber>;
    totalSteps: z.ZodDefault<z.ZodNumber>;
    requiredDocs: z.ZodDefault<z.ZodArray<z.ZodString>>;
}, z.core.$strip>, z.ZodObject<{
    type: z.ZodLiteral<"PortfolioSummary">;
    showSensitiveValues: z.ZodDefault<z.ZodBoolean>;
}, z.core.$strip>], "type">;
export type WidgetProps = z.infer<typeof WidgetSchema>;
export declare const UIPlanSchema: z.ZodObject<{
    version: z.ZodLiteral<"1.0">;
    generatedFor: z.ZodObject<{
        userId: z.ZodNumber;
        persona: z.ZodEnum<{
            Newbie: "Newbie";
            Scalper: "Scalper";
            Passive: "Passive";
            Whale: "Whale";
        }>;
        intent: z.ZodEnum<{
            VIEW_MARKET: "VIEW_MARKET";
            EXECUTE_TRADE: "EXECUTE_TRADE";
            ONBOARDING: "ONBOARDING";
        }>;
    }, z.core.$strip>;
    layout: z.ZodArray<z.ZodObject<{
        id: z.ZodString;
        colSpan: z.ZodDefault<z.ZodUnion<readonly [z.ZodLiteral<1>, z.ZodLiteral<2>, z.ZodLiteral<3>]>>;
        priority: z.ZodDefault<z.ZodNumber>;
        widget: z.ZodDiscriminatedUnion<[z.ZodObject<{
            type: z.ZodLiteral<"SimpleChart">;
            symbol: z.ZodString;
            color: z.ZodDefault<z.ZodEnum<{
                green: "green";
                red: "red";
                neutral: "neutral";
            }>>;
            period: z.ZodDefault<z.ZodEnum<{
                "24h": "24h";
                "7d": "7d";
            }>>;
        }, z.core.$strip>, z.ZodObject<{
            type: z.ZodLiteral<"ProChart">;
            symbol: z.ZodString;
            interval: z.ZodDefault<z.ZodEnum<{
                "1m": "1m";
                "15m": "15m";
                "1h": "1h";
                "4h": "4h";
                "1d": "1d";
            }>>;
            overlays: z.ZodOptional<z.ZodArray<z.ZodString>>;
        }, z.core.$strip>, z.ZodObject<{
            type: z.ZodLiteral<"OrderBook">;
            symbol: z.ZodString;
            depth: z.ZodDefault<z.ZodNumber>;
        }, z.core.$strip>, z.ZodObject<{
            type: z.ZodLiteral<"TradeHistory">;
            symbol: z.ZodString;
            limit: z.ZodDefault<z.ZodNumber>;
        }, z.core.$strip>, z.ZodObject<{
            type: z.ZodLiteral<"QuickOrder">;
            symbol: z.ZodString;
            allowedTypes: z.ZodArray<z.ZodEnum<{
                MARKET: "MARKET";
                LIMIT: "LIMIT";
                STOP_LOSS: "STOP_LOSS";
            }>>;
            defaultSide: z.ZodDefault<z.ZodEnum<{
                BUY: "BUY";
                SELL: "SELL";
            }>>;
        }, z.core.$strip>, z.ZodObject<{
            type: z.ZodLiteral<"RiskWarning">;
            level: z.ZodDefault<z.ZodEnum<{
                INFO: "INFO";
                WARNING: "WARNING";
                CRITICAL: "CRITICAL";
            }>>;
            message: z.ZodString;
            mustAcknowledge: z.ZodDefault<z.ZodBoolean>;
        }, z.core.$strip>, z.ZodObject<{
            type: z.ZodLiteral<"Onboarding">;
            currentStep: z.ZodDefault<z.ZodNumber>;
            totalSteps: z.ZodDefault<z.ZodNumber>;
            requiredDocs: z.ZodDefault<z.ZodArray<z.ZodString>>;
        }, z.core.$strip>, z.ZodObject<{
            type: z.ZodLiteral<"PortfolioSummary">;
            showSensitiveValues: z.ZodDefault<z.ZodBoolean>;
        }, z.core.$strip>], "type">;
    }, z.core.$strip>>;
}, z.core.$strip>;
export type UIPlan = z.infer<typeof UIPlanSchema>;
