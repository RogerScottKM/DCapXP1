import { Decimal } from "@prisma/client/runtime/library";

export type Decimalish = string | number | Decimal;

function toDecimal(value: Decimalish): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

// ─── Order status constants ──────────────────────────────
// Mirrors the Prisma OrderStatus enum after migration.
export const ORDER_STATUS = {
  OPEN: "OPEN",
  PARTIALLY_FILLED: "PARTIALLY_FILLED",
  FILLED: "FILLED",
  CANCEL_PENDING: "CANCEL_PENDING",
  CANCELLED: "CANCELLED",
} as const;

export type OrderStatusValue = (typeof ORDER_STATUS)[keyof typeof ORDER_STATUS];

// ─── Valid state transitions ─────────────────────────────
//
//  OPEN ─────────────► PARTIALLY_FILLED ───► FILLED
//   │                        │
//   ▼                        ▼
//  CANCEL_PENDING ──► CANCELLED (releases remaining held)
//
// FILLED and CANCELLED are terminal states.
const VALID_TRANSITIONS: Record<string, Set<string>> = {
  [ORDER_STATUS.OPEN]: new Set([
    ORDER_STATUS.PARTIALLY_FILLED,
    ORDER_STATUS.FILLED,
    ORDER_STATUS.CANCEL_PENDING,
    ORDER_STATUS.CANCELLED,
  ]),
  [ORDER_STATUS.PARTIALLY_FILLED]: new Set([
    ORDER_STATUS.PARTIALLY_FILLED, // additional fills
    ORDER_STATUS.FILLED,
    ORDER_STATUS.CANCEL_PENDING,
    ORDER_STATUS.CANCELLED,
  ]),
  [ORDER_STATUS.CANCEL_PENDING]: new Set([
    ORDER_STATUS.CANCELLED,
    // A fill can still land while cancel is pending (race condition).
    // In that case we go back to PARTIALLY_FILLED, then re-cancel.
    ORDER_STATUS.PARTIALLY_FILLED,
    ORDER_STATUS.FILLED,
  ]),
  [ORDER_STATUS.FILLED]: new Set([]),
  [ORDER_STATUS.CANCELLED]: new Set([]),
};

// ─── Qty helpers ─────────────────────────────────────────

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
    throw new Error(
      `Executed quantity exceeds order quantity: ${executed.toString()} > ${order.toString()}`,
    );
  }
}

// ─── Status derivation ───────────────────────────────────

/**
 * Derives the correct order status from current state and fill progress.
 *
 * Rules:
 *  - Terminal states (FILLED, CANCELLED) are preserved.
 *  - If fully filled → FILLED.
 *  - If partially filled (executedQty > 0 but < orderQty) → PARTIALLY_FILLED.
 *  - If no fills yet → preserve current (OPEN or CANCEL_PENDING).
 */
export function deriveOrderStatus(
  currentStatus: string,
  orderQty: Decimalish,
  executedQty: Decimalish,
): OrderStatusValue {
  // Terminal states are never changed
  if (currentStatus === ORDER_STATUS.CANCELLED) {
    return ORDER_STATUS.CANCELLED;
  }
  if (currentStatus === ORDER_STATUS.FILLED) {
    return ORDER_STATUS.FILLED;
  }

  const executed = toDecimal(executedQty);
  const order = toDecimal(orderQty);

  if (executed.greaterThanOrEqualTo(order)) {
    return ORDER_STATUS.FILLED;
  }

  if (executed.greaterThan(0)) {
    return ORDER_STATUS.PARTIALLY_FILLED;
  }

  // No fills yet — keep current state (OPEN or CANCEL_PENDING)
  if (currentStatus === ORDER_STATUS.CANCEL_PENDING) {
    return ORDER_STATUS.CANCEL_PENDING;
  }

  return ORDER_STATUS.OPEN;
}

// ─── Transition validation ───────────────────────────────

export function assertValidTransition(from: string, to: string): void {
  if (from === to) return; // no-op transitions are always valid

  const allowed = VALID_TRANSITIONS[from];
  if (!allowed || !allowed.has(to)) {
    throw new Error(
      `Invalid order status transition: ${from} → ${to}`,
    );
  }
}

/**
 * Returns true if the order can still accept fills.
 * CANCEL_PENDING can receive fills (race condition with matching engine).
 */
export function canReceiveFills(status: string): boolean {
  return (
    status === ORDER_STATUS.OPEN ||
    status === ORDER_STATUS.PARTIALLY_FILLED ||
    status === ORDER_STATUS.CANCEL_PENDING
  );
}

/**
 * Returns true if the order can be cancelled.
 */
export function canCancel(status: string): boolean {
  return (
    status === ORDER_STATUS.OPEN ||
    status === ORDER_STATUS.PARTIALLY_FILLED
  );
}
