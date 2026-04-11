import { Decimal } from "@prisma/client/runtime/library";

export type Decimalish = string | number | Decimal;

function toDecimal(value: Decimalish): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

export function computeRemainingQty(orderQty: Decimalish, executedQty: Decimalish): Decimal {
  const remaining = toDecimal(orderQty).minus(toDecimal(executedQty));
  return remaining.lessThan(0) ? new Decimal(0) : remaining;
}

export function isFullyFilled(orderQty: Decimalish, executedQty: Decimalish): boolean {
  return computeRemainingQty(orderQty, executedQty).lessThanOrEqualTo(0);
}

export function assertExecutedQtyWithinOrder(orderQty: Decimalish, executedQty: Decimalish): void {
  const order = toDecimal(orderQty);
  const executed = toDecimal(executedQty);
  if (executed.greaterThan(order)) {
    throw new Error(`Executed quantity exceeds order quantity: ${executed.toString()} > ${order.toString()}`);
  }
}

export function deriveOrderStatus(currentStatus: string, orderQty: Decimalish, executedQty: Decimalish): string {
  if (currentStatus === "CANCELLED") {
    return "CANCELLED";
  }
  return isFullyFilled(orderQty, executedQty) ? "FILLED" : "OPEN";
}
