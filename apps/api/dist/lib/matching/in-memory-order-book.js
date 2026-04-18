"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.InMemoryOrderBook = void 0;
const library_1 = require("@prisma/client/runtime/library");
const matching_priority_1 = require("../ledger/matching-priority");
const time_in_force_1 = require("../ledger/time-in-force");
function toDecimal(value) {
    return value instanceof library_1.Decimal ? value : new library_1.Decimal(value);
}
function minDecimal(a, b) {
    return a.lessThanOrEqualTo(b) ? a : b;
}
class InMemoryOrderBook {
    bids = [];
    asks = [];
    add(order) {
        const normalized = {
            ...order,
            price: toDecimal(order.price),
            remainingQty: toDecimal(order.remainingQty),
            createdAt: order.createdAt instanceof Date ? order.createdAt : new Date(order.createdAt ?? Date.now()),
        };
        const side = normalized.side === "BUY" ? this.bids : this.asks;
        side.push(normalized);
        return normalized;
    }
    remove(orderId) {
        const before = this.bids.length + this.asks.length;
        const nextBids = this.bids.filter((o) => o.orderId !== orderId);
        const nextAsks = this.asks.filter((o) => o.orderId !== orderId);
        this.bids.splice(0, this.bids.length, ...nextBids);
        this.asks.splice(0, this.asks.length, ...nextAsks);
        return before !== this.bids.length + this.asks.length;
    }
    snapshot(side) {
        const source = side === "BUY" ? this.bids : this.asks;
        return source.map((o) => ({ ...o }));
    }
    oppositeFor(side) {
        return side === "BUY" ? this.asks : this.bids;
    }
    getBestOppositePrice(side) {
        const sortedOpposite = (0, matching_priority_1.sortMakersForTaker)(side, this.oppositeFor(side));
        return sortedOpposite[0]?.price ?? null;
    }
    getCrossingLiquidity(side, takerPrice) {
        const price = toDecimal(takerPrice);
        let total = new library_1.Decimal(0);
        for (const maker of (0, matching_priority_1.sortMakersForTaker)(side, this.oppositeFor(side))) {
            const crosses = side === "BUY"
                ? maker.price.lessThanOrEqualTo(price)
                : maker.price.greaterThanOrEqualTo(price);
            if (!crosses)
                break;
            if (maker.remainingQty.lessThanOrEqualTo(0))
                continue;
            total = total.plus(maker.remainingQty);
        }
        return total;
    }
    summarizeSide(sideOrders) {
        const active = sideOrders.filter((o) => o.remainingQty.greaterThan(0));
        if (!active.length) {
            return { bestPrice: null, depth: "0", count: 0 };
        }
        const total = active.reduce((acc, order) => acc.plus(order.remainingQty), new library_1.Decimal(0));
        const best = active[0]?.price ?? null;
        return {
            bestPrice: best ? best.toString() : null,
            depth: total.toString(),
            count: active.length,
        };
    }
    getBookDelta(symbol) {
        const sortedBids = (0, matching_priority_1.sortMakersForTaker)("SELL", this.bids);
        const sortedAsks = (0, matching_priority_1.sortMakersForTaker)("BUY", this.asks);
        const bidSummary = this.summarizeSide(sortedBids);
        const askSummary = this.summarizeSide(sortedAsks);
        return {
            symbol,
            bestBid: bidSummary.bestPrice,
            bestAsk: askSummary.bestPrice,
            bidDepth: bidSummary.depth,
            askDepth: askSummary.depth,
            bidOrders: bidSummary.count,
            askOrders: askSummary.count,
        };
    }
    matchIncoming(input) {
        const tif = (0, time_in_force_1.normalizeTimeInForce)(input.timeInForce);
        const takerPrice = toDecimal(input.price);
        const initialQty = toDecimal(input.qty);
        let remaining = initialQty;
        const bestOppositePrice = this.getBestOppositePrice(input.side);
        if (tif === "POST_ONLY") {
            (0, time_in_force_1.assertPostOnlyWouldRest)(input.side, takerPrice, bestOppositePrice);
        }
        if (tif === "FOK") {
            const fillableLiquidity = this.getCrossingLiquidity(input.side, takerPrice);
            (0, time_in_force_1.assertFokCanFullyFill)(initialQty, fillableLiquidity);
        }
        const fills = [];
        const sortedOpposite = (0, matching_priority_1.sortMakersForTaker)(input.side, this.oppositeFor(input.side));
        for (const maker of sortedOpposite) {
            if (remaining.lessThanOrEqualTo(0))
                break;
            const crosses = input.side === "BUY"
                ? maker.price.lessThanOrEqualTo(takerPrice)
                : maker.price.greaterThanOrEqualTo(takerPrice);
            if (!crosses)
                break;
            if (maker.remainingQty.lessThanOrEqualTo(0))
                continue;
            const fillQty = minDecimal(remaining, maker.remainingQty);
            maker.remainingQty = maker.remainingQty.minus(fillQty);
            remaining = remaining.minus(fillQty);
            fills.push({
                makerOrderId: maker.orderId,
                takerOrderId: input.orderId,
                qty: fillQty.toString(),
                price: maker.price.toString(),
            });
            if (maker.remainingQty.lessThanOrEqualTo(0)) {
                this.remove(maker.orderId);
            }
            else {
                const bookSide = maker.side === "BUY" ? this.bids : this.asks;
                const idx = bookSide.findIndex((o) => o.orderId === maker.orderId);
                if (idx >= 0) {
                    bookSide[idx] = maker;
                }
            }
        }
        const executedQty = initialQty.minus(remaining);
        const tifAction = (0, time_in_force_1.deriveTifRestingAction)(tif, executedQty, initialQty);
        let restingOrderId = null;
        if (tifAction === "KEEP_OPEN" && remaining.greaterThan(0)) {
            const resting = this.add({
                orderId: input.orderId,
                symbol: input.symbol,
                side: input.side,
                price: takerPrice,
                remainingQty: remaining,
                createdAt: input.createdAt,
                timeInForce: tif,
            });
            restingOrderId = resting.orderId;
        }
        return {
            fills,
            remainingQty: remaining.toString(),
            tifAction,
            restingOrderId,
            bookDelta: this.getBookDelta(input.symbol),
        };
    }
}
exports.InMemoryOrderBook = InMemoryOrderBook;
