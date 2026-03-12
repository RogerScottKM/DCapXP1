import type { PlanContext } from "./types";

const SAFE_SYMBOLS = new Set(["BTC-USD", "ETH-USD", "SOL-USD"]); // v0 allowlist

export function policyFor(ctx: PlanContext) {
  const isNewbie = ctx.persona === "Newbie";
  const isWhale = ctx.persona === "Whale";

  return {
    // Semantics validation lives here (not Zod):
    symbolAllowed: SAFE_SYMBOLS.has(ctx.symbol),
    showRiskBanner: true,

    allowOrderEntry: true, // keep on for demo
    allowedOrderTypes: isNewbie
      ? (["MARKET", "LIMIT"] as const)
      : (["MARKET", "LIMIT", "STOP_LOSS"] as const),

    // placeholder for later leverage/margin policy
    allowLeverage: isWhale,
  };
}
