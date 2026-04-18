"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildMakerOrderByForTaker = buildMakerOrderByForTaker;
exports.compareMakerPriority = compareMakerPriority;
exports.sortMakersForTaker = sortMakersForTaker;
const library_1 = require("@prisma/client/runtime/library");
function toDecimal(value) {
    return value instanceof library_1.Decimal ? value : new library_1.Decimal(value);
}
function toTimestamp(value) {
    if (value instanceof Date)
        return value.getTime();
    return new Date(value).getTime();
}
function buildMakerOrderByForTaker(side) {
    return side === "BUY"
        ? [{ price: "asc" }, { createdAt: "asc" }]
        : [{ price: "desc" }, { createdAt: "asc" }];
}
function compareMakerPriority(takerSide, a, b) {
    const priceA = toDecimal(a.price);
    const priceB = toDecimal(b.price);
    if (!priceA.eq(priceB)) {
        if (takerSide === "BUY") {
            return priceA.lessThan(priceB) ? -1 : 1;
        }
        return priceA.greaterThan(priceB) ? -1 : 1;
    }
    const tsA = toTimestamp(a.createdAt);
    const tsB = toTimestamp(b.createdAt);
    if (tsA < tsB)
        return -1;
    if (tsA > tsB)
        return 1;
    return 0;
}
function sortMakersForTaker(takerSide, makers) {
    return [...makers].sort((a, b) => compareMakerPriority(takerSide, a, b));
}
