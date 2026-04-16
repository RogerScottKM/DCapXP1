"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ORDER_STATUS = void 0;
exports.computeRemainingQty = computeRemainingQty;
exports.isFullyFilled = isFullyFilled;
exports.assertExecutedQtyWithinOrder = assertExecutedQtyWithinOrder;
exports.deriveOrderStatus = deriveOrderStatus;
exports.assertValidTransition = assertValidTransition;
exports.canReceiveFills = canReceiveFills;
exports.canCancel = canCancel;
const library_1 = require("@prisma/client/runtime/library");
function toDecimal(value) {
    return value instanceof library_1.Decimal ? value : new library_1.Decimal(value);
}
// ─── Order status constants ──────────────────────────────
// Mirrors the Prisma OrderStatus enum after migration.
exports.ORDER_STATUS = {
    OPEN: "OPEN",
    PARTIALLY_FILLED: "PARTIALLY_FILLED",
    FILLED: "FILLED",
    CANCEL_PENDING: "CANCEL_PENDING",
    CANCELLED: "CANCELLED",
};
// ─── Valid state transitions ─────────────────────────────
//
//  OPEN ─────────────► PARTIALLY_FILLED ───► FILLED
//   │                        │
//   ▼                        ▼
//  CANCEL_PENDING ──► CANCELLED (releases remaining held)
//
// FILLED and CANCELLED are terminal states.
const VALID_TRANSITIONS = {
    [exports.ORDER_STATUS.OPEN]: new Set([
        exports.ORDER_STATUS.PARTIALLY_FILLED,
        exports.ORDER_STATUS.FILLED,
        exports.ORDER_STATUS.CANCEL_PENDING,
        exports.ORDER_STATUS.CANCELLED,
    ]),
    [exports.ORDER_STATUS.PARTIALLY_FILLED]: new Set([
        exports.ORDER_STATUS.PARTIALLY_FILLED, // additional fills
        exports.ORDER_STATUS.FILLED,
        exports.ORDER_STATUS.CANCEL_PENDING,
        exports.ORDER_STATUS.CANCELLED,
    ]),
    [exports.ORDER_STATUS.CANCEL_PENDING]: new Set([
        exports.ORDER_STATUS.CANCELLED,
        // A fill can still land while cancel is pending (race condition).
        // In that case we go back to PARTIALLY_FILLED, then re-cancel.
        exports.ORDER_STATUS.PARTIALLY_FILLED,
        exports.ORDER_STATUS.FILLED,
    ]),
    [exports.ORDER_STATUS.FILLED]: new Set([]),
    [exports.ORDER_STATUS.CANCELLED]: new Set([]),
};
// ─── Qty helpers ─────────────────────────────────────────
function computeRemainingQty(orderQty, executedQty) {
    const remaining = toDecimal(orderQty).minus(toDecimal(executedQty));
    return remaining.lessThan(0) ? new library_1.Decimal(0) : remaining;
}
function isFullyFilled(orderQty, executedQty) {
    return computeRemainingQty(orderQty, executedQty).lessThanOrEqualTo(0);
}
function assertExecutedQtyWithinOrder(orderQty, executedQty) {
    const order = toDecimal(orderQty);
    const executed = toDecimal(executedQty);
    if (executed.greaterThan(order)) {
        throw new Error(`Executed quantity exceeds order quantity: ${executed.toString()} > ${order.toString()}`);
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
function deriveOrderStatus(currentStatus, orderQty, executedQty) {
    // Terminal states are never changed
    if (currentStatus === exports.ORDER_STATUS.CANCELLED) {
        return exports.ORDER_STATUS.CANCELLED;
    }
    if (currentStatus === exports.ORDER_STATUS.FILLED) {
        return exports.ORDER_STATUS.FILLED;
    }
    const executed = toDecimal(executedQty);
    const order = toDecimal(orderQty);
    if (executed.greaterThanOrEqualTo(order)) {
        return exports.ORDER_STATUS.FILLED;
    }
    if (executed.greaterThan(0)) {
        return exports.ORDER_STATUS.PARTIALLY_FILLED;
    }
    // No fills yet — keep current state (OPEN or CANCEL_PENDING)
    if (currentStatus === exports.ORDER_STATUS.CANCEL_PENDING) {
        return exports.ORDER_STATUS.CANCEL_PENDING;
    }
    return exports.ORDER_STATUS.OPEN;
}
// ─── Transition validation ───────────────────────────────
function assertValidTransition(from, to) {
    if (from === to)
        return; // no-op transitions are always valid
    const allowed = VALID_TRANSITIONS[from];
    if (!allowed || !allowed.has(to)) {
        throw new Error(`Invalid order status transition: ${from} → ${to}`);
    }
}
/**
 * Returns true if the order can still accept fills.
 * CANCEL_PENDING can receive fills (race condition with matching engine).
 */
function canReceiveFills(status) {
    return (status === exports.ORDER_STATUS.OPEN ||
        status === exports.ORDER_STATUS.PARTIALLY_FILLED ||
        status === exports.ORDER_STATUS.CANCEL_PENDING);
}
/**
 * Returns true if the order can be cancelled.
 */
function canCancel(status) {
    return (status === exports.ORDER_STATUS.OPEN ||
        status === exports.ORDER_STATUS.PARTIALLY_FILLED);
}
