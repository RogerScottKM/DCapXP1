import { Decimal } from "@prisma/client/runtime/library";

function toDecimal(value: string | number | Decimal): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

export function computeExecutedQuote(
  executedQty: string | number | Decimal,
  executionPrice: string | number | Decimal,
): Decimal {
  return toDecimal(executedQty).mul(toDecimal(executionPrice));
}

export function computeReservedQuote(
  orderQty: string | number | Decimal,
  limitPrice: string | number | Decimal,
): Decimal {
  return toDecimal(orderQty).mul(toDecimal(limitPrice));
}

export function computeRemainingQtyFromCumulative(
  orderQty: string | number | Decimal,
  cumulativeFilledQty: string | number | Decimal,
): Decimal {
  const remaining = toDecimal(orderQty).sub(toDecimal(cumulativeFilledQty));
  return remaining.lessThan(0) ? new Decimal(0) : remaining;
}

export function assertCumulativeFillWithinOrder(
  orderQty: string | number | Decimal,
  cumulativeFilledQty: string | number | Decimal,
): void {
  if (toDecimal(cumulativeFilledQty).greaterThan(toDecimal(orderQty))) {
    throw new Error("Cumulative filled quantity cannot exceed order quantity.");
  }
}

export function computeBuyHeldQuoteRelease(params: {
  orderQty: string | number | Decimal;
  limitPrice: string | number | Decimal;
  cumulativeFilledQty: string | number | Decimal;
  weightedExecutedQuote: string | number | Decimal;
}): Decimal {
  const remainingQty = computeRemainingQtyFromCumulative(
    params.orderQty,
    params.cumulativeFilledQty,
  );

  if (remainingQty.greaterThan(0)) {
    return new Decimal(0);
  }

  const reserved = computeReservedQuote(params.orderQty, params.limitPrice);
  const spent = toDecimal(params.weightedExecutedQuote);
  const release = reserved.sub(spent);
  return release.lessThan(0) ? new Decimal(0) : release;
}
