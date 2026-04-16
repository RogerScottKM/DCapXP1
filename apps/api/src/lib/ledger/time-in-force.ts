import { Decimal } from "@prisma/client/runtime/library";

export type Decimalish = string | number | Decimal;

function toDecimal(value: Decimalish): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

export const ORDER_TIF = {
  GTC: "GTC",
  IOC: "IOC",
  FOK: "FOK",
  POST_ONLY: "POST_ONLY",
} as const;

export type TimeInForceValue = (typeof ORDER_TIF)[keyof typeof ORDER_TIF];

export function normalizeTimeInForce(value?: string | null): TimeInForceValue {
  const normalized = String(value ?? "GTC").trim().toUpperCase();
  if (normalized === ORDER_TIF.IOC) return ORDER_TIF.IOC;
  if (normalized === ORDER_TIF.FOK) return ORDER_TIF.FOK;
  if (normalized === ORDER_TIF.POST_ONLY) return ORDER_TIF.POST_ONLY;
  return ORDER_TIF.GTC;
}

export function wouldLimitOrderCrossBestQuote(
  side: "BUY" | "SELL",
  limitPrice: Decimalish,
  bestOppositePrice: Decimalish | null | undefined,
): boolean {
  if (bestOppositePrice === null || bestOppositePrice === undefined) return false;

  const limit = toDecimal(limitPrice);
  const opposite = toDecimal(bestOppositePrice);

  return side === "BUY"
    ? opposite.lessThanOrEqualTo(limit)
    : opposite.greaterThanOrEqualTo(limit);
}

export function assertPostOnlyWouldRest(
  side: "BUY" | "SELL",
  limitPrice: Decimalish,
  bestOppositePrice: Decimalish | null | undefined,
): void {
  if (wouldLimitOrderCrossBestQuote(side, limitPrice, bestOppositePrice)) {
    throw new Error("POST_ONLY order would cross the book.");
  }
}

export function assertFokCanFullyFill(orderQty: Decimalish, fillableQty: Decimalish): void {
  const order = toDecimal(orderQty);
  const fillable = toDecimal(fillableQty);
  if (fillable.lessThan(order)) {
    throw new Error("FOK order cannot be fully filled.");
  }
}

export function deriveTifRestingAction(
  timeInForce: string,
  executedQty: Decimalish,
  orderQty: Decimalish,
): "KEEP_OPEN" | "CANCEL_REMAINDER" | "FILLED" {
  const tif = normalizeTimeInForce(timeInForce);
  const executed = toDecimal(executedQty);
  const order = toDecimal(orderQty);

  if (executed.greaterThanOrEqualTo(order)) {
    return "FILLED";
  }

  if (tif === ORDER_TIF.IOC || tif === ORDER_TIF.FOK) {
    return "CANCEL_REMAINDER";
  }

  return "KEEP_OPEN";
}
