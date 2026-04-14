"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.computeRemainingQty = computeRemainingQty;
exports.isFullyFilled = isFullyFilled;
exports.assertExecutedQtyWithinOrder = assertExecutedQtyWithinOrder;
exports.deriveOrderStatus = deriveOrderStatus;
const library_1 = require("@prisma/client/runtime/library");
function toDecimal(value) {
    return value instanceof library_1.Decimal ? value : new library_1.Decimal(value);
}
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
function deriveOrderStatus(currentStatus, orderQty, executedQty) {
    if (currentStatus === "CANCELLED") {
        return "CANCELLED";
    }
    return isFullyFilled(orderQty, executedQty) ? "FILLED" : "OPEN";
}
