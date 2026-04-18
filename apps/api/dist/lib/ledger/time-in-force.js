"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ORDER_TIF = void 0;
exports.normalizeTimeInForce = normalizeTimeInForce;
exports.wouldLimitOrderCrossBestQuote = wouldLimitOrderCrossBestQuote;
exports.assertPostOnlyWouldRest = assertPostOnlyWouldRest;
exports.assertFokCanFullyFill = assertFokCanFullyFill;
exports.deriveTifRestingAction = deriveTifRestingAction;
const library_1 = require("@prisma/client/runtime/library");
function toDecimal(value) {
    return value instanceof library_1.Decimal ? value : new library_1.Decimal(value);
}
exports.ORDER_TIF = {
    GTC: "GTC",
    IOC: "IOC",
    FOK: "FOK",
    POST_ONLY: "POST_ONLY",
};
function normalizeTimeInForce(value) {
    const normalized = String(value ?? "GTC").trim().toUpperCase();
    if (normalized === exports.ORDER_TIF.IOC)
        return exports.ORDER_TIF.IOC;
    if (normalized === exports.ORDER_TIF.FOK)
        return exports.ORDER_TIF.FOK;
    if (normalized === exports.ORDER_TIF.POST_ONLY)
        return exports.ORDER_TIF.POST_ONLY;
    return exports.ORDER_TIF.GTC;
}
function wouldLimitOrderCrossBestQuote(side, limitPrice, bestOppositePrice) {
    if (bestOppositePrice === null || bestOppositePrice === undefined)
        return false;
    const limit = toDecimal(limitPrice);
    const opposite = toDecimal(bestOppositePrice);
    return side === "BUY"
        ? opposite.lessThanOrEqualTo(limit)
        : opposite.greaterThanOrEqualTo(limit);
}
function assertPostOnlyWouldRest(side, limitPrice, bestOppositePrice) {
    if (wouldLimitOrderCrossBestQuote(side, limitPrice, bestOppositePrice)) {
        throw new Error("POST_ONLY order would cross the book.");
    }
}
function assertFokCanFullyFill(orderQty, fillableQty) {
    const order = toDecimal(orderQty);
    const fillable = toDecimal(fillableQty);
    if (fillable.lessThan(order)) {
        throw new Error("FOK order cannot be fully filled.");
    }
}
function deriveTifRestingAction(timeInForce, executedQty, orderQty) {
    const tif = normalizeTimeInForce(timeInForce);
    const executed = toDecimal(executedQty);
    const order = toDecimal(orderQty);
    if (executed.greaterThanOrEqualTo(order)) {
        return "FILLED";
    }
    if (tif === exports.ORDER_TIF.IOC || tif === exports.ORDER_TIF.FOK) {
        return "CANCEL_REMAINDER";
    }
    return "KEEP_OPEN";
}
