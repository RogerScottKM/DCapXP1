"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.computeExecutedQuote = computeExecutedQuote;
exports.computeReservedQuote = computeReservedQuote;
exports.computeRemainingQtyFromCumulative = computeRemainingQtyFromCumulative;
exports.assertCumulativeFillWithinOrder = assertCumulativeFillWithinOrder;
exports.computeBuyHeldQuoteRelease = computeBuyHeldQuoteRelease;
const library_1 = require("@prisma/client/runtime/library");
function toDecimal(value) {
    return value instanceof library_1.Decimal ? value : new library_1.Decimal(value);
}
function computeExecutedQuote(executedQty, executionPrice) {
    return toDecimal(executedQty).mul(toDecimal(executionPrice));
}
function computeReservedQuote(orderQty, limitPrice) {
    return toDecimal(orderQty).mul(toDecimal(limitPrice));
}
function computeRemainingQtyFromCumulative(orderQty, cumulativeFilledQty) {
    const remaining = toDecimal(orderQty).sub(toDecimal(cumulativeFilledQty));
    return remaining.lessThan(0) ? new library_1.Decimal(0) : remaining;
}
function assertCumulativeFillWithinOrder(orderQty, cumulativeFilledQty) {
    if (toDecimal(cumulativeFilledQty).greaterThan(toDecimal(orderQty))) {
        throw new Error("Cumulative filled quantity cannot exceed order quantity.");
    }
}
function computeBuyHeldQuoteRelease(params) {
    const remainingQty = computeRemainingQtyFromCumulative(params.orderQty, params.cumulativeFilledQty);
    if (remainingQty.greaterThan(0)) {
        return new library_1.Decimal(0);
    }
    const reserved = computeReservedQuote(params.orderQty, params.limitPrice);
    const spent = toDecimal(params.weightedExecutedQuote);
    const release = reserved.sub(spent);
    return release.lessThan(0) ? new library_1.Decimal(0) : release;
}
