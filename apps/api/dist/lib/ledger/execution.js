"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.isCrossingLimitOrder = isCrossingLimitOrder;
exports.computeQuoteFeeAmount = computeQuoteFeeAmount;
exports.computeBuyPriceImprovementReleaseAmount = computeBuyPriceImprovementReleaseAmount;
exports.getOrderExecutedQty = getOrderExecutedQty;
exports.getOrderRemainingQty = getOrderRemainingQty;
exports.syncOrderStatusFromTrades = syncOrderStatusFromTrades;
exports.releaseBuyPriceImprovement = releaseBuyPriceImprovement;
exports.executeLimitOrderAgainstBook = executeLimitOrderAgainstBook;
exports.reconcileOrderExecution = reconcileOrderExecution;
exports.releaseResidualHoldAfterExecution = releaseResidualHoldAfterExecution;
exports.reconcileCumulativeFills = reconcileCumulativeFills;
const library_1 = require("@prisma/client/runtime/library");
const prisma_1 = require("../prisma");
const accounts_1 = require("./accounts");
const order_lifecycle_1 = require("./order-lifecycle");
const order_state_1 = require("./order-state");
const time_in_force_1 = require("./time-in-force");
const reconciliation_1 = require("./reconciliation");
const service_1 = require("./service");
const matching_priority_1 = require("./matching-priority");
const hold_release_1 = require("./hold-release");
function toDecimal(value) {
    return value instanceof library_1.Decimal ? value : new library_1.Decimal(value);
}
function minDecimal(a, b) {
    return a.lessThanOrEqualTo(b) ? a : b;
}
function isCrossingLimitOrder(takerSide, takerPrice, makerPrice) {
    const taker = toDecimal(takerPrice);
    const maker = toDecimal(makerPrice);
    return takerSide === "BUY" ? maker.lessThanOrEqualTo(taker) : maker.greaterThanOrEqualTo(taker);
}
function computeQuoteFeeAmount(grossQuote, quoteFeeBps = 0) {
    const gross = toDecimal(grossQuote);
    const bps = toDecimal(quoteFeeBps);
    if (gross.lessThanOrEqualTo(0) || bps.lessThanOrEqualTo(0)) {
        return new library_1.Decimal(0);
    }
    return gross.mul(bps).div(10_000);
}
function computeBuyPriceImprovementReleaseAmount(limitPrice, executionPrice, fillQty) {
    const limit = toDecimal(limitPrice);
    const execution = toDecimal(executionPrice);
    const qty = toDecimal(fillQty);
    if (qty.lessThanOrEqualTo(0) || execution.greaterThanOrEqualTo(limit)) {
        return new library_1.Decimal(0);
    }
    return limit.minus(execution).mul(qty);
}
async function getOrderExecutedQty(orderId, db = prisma_1.prisma) {
    const normalizedId = BigInt(String(orderId));
    const [buyAgg, sellAgg] = await Promise.all([
        db.trade.aggregate({ where: { buyOrderId: normalizedId }, _sum: { qty: true } }),
        db.trade.aggregate({ where: { sellOrderId: normalizedId }, _sum: { qty: true } }),
    ]);
    const buyQty = buyAgg._sum.qty ? new library_1.Decimal(buyAgg._sum.qty) : new library_1.Decimal(0);
    const sellQty = sellAgg._sum.qty ? new library_1.Decimal(sellAgg._sum.qty) : new library_1.Decimal(0);
    return buyQty.plus(sellQty);
}
async function getOrderRemainingQty(order, db = prisma_1.prisma) {
    const executed = await getOrderExecutedQty(order.id, db);
    (0, order_state_1.assertExecutedQtyWithinOrder)(order.qty, executed);
    return (0, order_state_1.computeRemainingQty)(order.qty, executed);
}
async function syncOrderStatusFromTrades(orderId, db = prisma_1.prisma) {
    const normalizedId = BigInt(String(orderId));
    const order = await db.order.findUniqueOrThrow({ where: { id: normalizedId } });
    const executed = await getOrderExecutedQty(order.id, db);
    (0, order_state_1.assertExecutedQtyWithinOrder)(order.qty, executed);
    const nextStatus = (0, order_state_1.deriveOrderStatus)(order.status, order.qty, executed);
    (0, order_state_1.assertValidTransition)(order.status, nextStatus);
    return db.order.update({
        where: { id: order.id },
        data: {
            status: nextStatus,
        },
    });
}
async function findExistingReference(referenceType, referenceId, db) {
    return db.ledgerTransaction.findFirst({
        where: { referenceType, referenceId },
        include: { postings: true },
    });
}
async function releaseBuyPriceImprovement(input, db = prisma_1.prisma) {
    const releaseAmount = computeBuyPriceImprovementReleaseAmount(input.limitPrice, input.executionPrice, input.fillQty);
    if (releaseAmount.lessThanOrEqualTo(0)) {
        return null;
    }
    const referenceType = "ORDER_EVENT";
    const referenceId = `${input.tradeRef}:BUY_PRICE_IMPROVEMENT:${String(input.orderId)}`;
    const existing = await findExistingReference(referenceType, referenceId, db);
    if (existing) {
        return existing;
    }
    const quoteAsset = input.symbol.split("-")[1] ?? input.symbol;
    const userQuoteAccounts = await (0, accounts_1.ensureUserLedgerAccounts)({
        userId: input.userId,
        assetCode: quoteAsset,
        mode: input.mode,
    }, db);
    return (0, service_1.postLedgerTransaction)({
        referenceType,
        referenceId,
        description: `Release quote price improvement for BUY order ${String(input.orderId)}`,
        metadata: {
            event: "ORDER_BUY_PRICE_IMPROVEMENT_RELEASE",
            tradeRef: input.tradeRef,
            orderId: String(input.orderId),
            symbol: input.symbol,
            userId: input.userId,
            mode: input.mode,
            releaseAmount: releaseAmount.toString(),
        },
        postings: [
            {
                accountId: userQuoteAccounts.held.id,
                assetCode: userQuoteAccounts.held.assetCode,
                side: "DEBIT",
                amount: releaseAmount,
            },
            {
                accountId: userQuoteAccounts.available.id,
                assetCode: userQuoteAccounts.available.assetCode,
                side: "CREDIT",
                amount: releaseAmount,
            },
        ],
    }, db);
}
async function getMatchingOrders(order, db) {
    const oppositeSide = order.side === "BUY" ? "SELL" : "BUY";
    const candidates = await db.order.findMany({
        where: {
            symbol: order.symbol,
            mode: order.mode,
            status: { in: [order_state_1.ORDER_STATUS.OPEN, order_state_1.ORDER_STATUS.PARTIALLY_FILLED] },
            side: oppositeSide,
            NOT: { id: order.id },
        },
        orderBy: (0, matching_priority_1.buildMakerOrderByForTaker)(order.side),
    });
    return candidates.filter((candidate) => isCrossingLimitOrder(order.side, order.price, candidate.price));
}
async function executeLimitOrderAgainstBook(input, db = prisma_1.prisma) {
    const orderId = BigInt(String(input.orderId));
    const takerOrder = await db.order.findUniqueOrThrow({ where: { id: orderId } });
    if (!(0, order_state_1.canReceiveFills)(takerOrder.status)) {
        throw new Error(`Order ${takerOrder.id} cannot receive fills in status ${takerOrder.status}.`);
    }
    if (!takerOrder.price) {
        throw new Error("Only LIMIT orders with a price can be executed.");
    }
    const tif = (0, time_in_force_1.normalizeTimeInForce)(takerOrder.timeInForce);
    const matches = await getMatchingOrders(takerOrder, db);
    if (tif === time_in_force_1.ORDER_TIF.POST_ONLY && matches.length > 0) {
        (0, time_in_force_1.assertPostOnlyWouldRest)(takerOrder.side, takerOrder.price, matches[0]?.price ?? null);
    }
    if (tif === time_in_force_1.ORDER_TIF.FOK) {
        let fillableLiquidity = new library_1.Decimal(0);
        for (const m of matches) {
            const freshMaker = await db.order.findUnique({ where: { id: m.id } });
            if (!freshMaker || !(0, order_state_1.canReceiveFills)(freshMaker.status)) {
                continue;
            }
            const mRemaining = await getOrderRemainingQty(freshMaker, db);
            fillableLiquidity = fillableLiquidity.plus(mRemaining);
        }
        (0, time_in_force_1.assertFokCanFullyFill)(takerOrder.qty, fillableLiquidity);
    }
    const fills = [];
    let remaining = await getOrderRemainingQty(takerOrder, db);
    for (const makerOrder of matches) {
        if (remaining.lessThanOrEqualTo(0)) {
            break;
        }
        const freshMaker = await db.order.findUnique({ where: { id: makerOrder.id } });
        if (!freshMaker || !(0, order_state_1.canReceiveFills)(freshMaker.status)) {
            continue;
        }
        const makerRemaining = await getOrderRemainingQty(freshMaker, db);
        if (makerRemaining.lessThanOrEqualTo(0)) {
            continue;
        }
        const fillQty = minDecimal(remaining, makerRemaining);
        const executionPrice = new library_1.Decimal(freshMaker.price);
        const grossQuote = fillQty.mul(executionPrice);
        const quoteFee = computeQuoteFeeAmount(grossQuote, input.quoteFeeBps ?? 0);
        const buyOrder = takerOrder.side === "BUY" ? takerOrder : freshMaker;
        const sellOrder = takerOrder.side === "SELL" ? takerOrder : freshMaker;
        const trade = await db.trade.create({
            data: {
                symbol: takerOrder.symbol,
                price: executionPrice,
                qty: fillQty,
                mode: takerOrder.mode,
                buyOrderId: buyOrder.id,
                sellOrderId: sellOrder.id,
            },
        });
        const ledgerSettlement = await (0, order_lifecycle_1.settleMatchedTrade)({
            tradeRef: trade.id.toString(),
            buyOrderId: buyOrder.id,
            sellOrderId: sellOrder.id,
            symbol: takerOrder.symbol,
            qty: fillQty,
            price: executionPrice,
            mode: takerOrder.mode,
            quoteFee,
        }, db);
        const buyPriceImprovementRelease = await releaseBuyPriceImprovement({
            tradeRef: trade.id.toString(),
            orderId: buyOrder.id,
            userId: buyOrder.userId,
            symbol: takerOrder.symbol,
            limitPrice: buyOrder.price,
            executionPrice,
            fillQty,
            mode: takerOrder.mode,
        }, db);
        const reconciliation = await (0, reconciliation_1.reconcileTradeSettlement)(trade.id, db);
        await syncOrderStatusFromTrades(buyOrder.id, db);
        await syncOrderStatusFromTrades(sellOrder.id, db);
        fills.push({
            trade,
            ledgerSettlement,
            reconciliation,
            buyPriceImprovementRelease,
        });
        remaining = remaining.minus(fillQty);
    }
    const executed = await getOrderExecutedQty(takerOrder.id, db);
    const tifAction = (0, time_in_force_1.deriveTifRestingAction)(tif, executed, takerOrder.qty);
    if (tifAction === "CANCEL_REMAINDER" && remaining.greaterThan(0)) {
        await (0, order_lifecycle_1.releaseOrderOnCancel)({
            orderId: takerOrder.id,
            userId: takerOrder.userId,
            symbol: takerOrder.symbol,
            side: takerOrder.side,
            qty: remaining,
            price: takerOrder.price,
            mode: takerOrder.mode,
            reason: "CANCEL",
        }, db);
        const currentDerivedStatus = (0, order_state_1.deriveOrderStatus)(takerOrder.status, takerOrder.qty, executed);
        (0, order_state_1.assertValidTransition)(currentDerivedStatus, order_state_1.ORDER_STATUS.CANCELLED);
        await db.order.update({
            where: { id: takerOrder.id },
            data: { status: order_state_1.ORDER_STATUS.CANCELLED },
        });
    }
    const refreshedOrder = await db.order.findUniqueOrThrow({ where: { id: takerOrder.id } });
    const refreshedRemaining = await getOrderRemainingQty(refreshedOrder, db);
    return {
        order: refreshedOrder,
        fills,
        remainingQty: refreshedRemaining.toString(),
        tifAction,
    };
}
async function reconcileOrderExecution(orderId, db = prisma_1.prisma) {
    const normalizedId = BigInt(String(orderId));
    const order = await db.order.findUniqueOrThrow({ where: { id: normalizedId } });
    const trades = await db.trade.findMany({
        where: {
            OR: [{ buyOrderId: normalizedId }, { sellOrderId: normalizedId }],
        },
        orderBy: { createdAt: "asc" },
    });
    const ledgerReferenceIds = trades.map((trade) => `${trade.id}:FILL_SETTLEMENT`);
    const ledgerTransactions = ledgerReferenceIds.length
        ? await db.ledgerTransaction.findMany({
            where: {
                referenceType: "ORDER_EVENT",
                referenceId: { in: ledgerReferenceIds },
            },
        })
        : [];
    const executedQty = trades.reduce((acc, trade) => acc.plus(new library_1.Decimal(trade.qty)), new library_1.Decimal(0));
    (0, order_state_1.assertExecutedQtyWithinOrder)(order.qty, executedQty);
    const safeRemaining = (0, order_state_1.computeRemainingQty)(order.qty, executedQty);
    if (ledgerTransactions.length !== trades.length) {
        throw new Error("Trade to ledger transaction count mismatch for order reconciliation.");
    }
    const expectedStatus = (0, order_state_1.deriveOrderStatus)(order.status, order.qty, executedQty);
    if (order.status !== expectedStatus) {
        throw new Error(`Order status mismatch: expected ${expectedStatus}, got ${order.status}`);
    }
    return {
        orderId: String(order.id),
        status: order.status,
        expectedStatus,
        tradeCount: trades.length,
        ledgerTransactionCount: ledgerTransactions.length,
        executedQty: executedQty.toString(),
        remainingQty: safeRemaining.toString(),
    };
}
function toDecimalExecution(value) {
    return value instanceof library_1.Decimal ? value : new library_1.Decimal(value);
}
async function releaseResidualHoldAfterExecution(params, db = prisma_1.prisma) {
    if (params.side !== "BUY") {
        return null;
    }
    const releaseAmount = (0, hold_release_1.computeBuyHeldQuoteRelease)({
        orderQty: params.orderQty,
        limitPrice: params.limitPrice,
        cumulativeFilledQty: params.cumulativeFilledQty,
        weightedExecutedQuote: params.weightedExecutedQuote ?? "0",
    });
    if (releaseAmount.lessThanOrEqualTo(0)) {
        return null;
    }
    const referenceType = "ORDER_RELEASE";
    const referenceId = `${params.orderId}:FINAL_RESIDUAL_RELEASE`;
    const existing = await findExistingReference(referenceType, referenceId, db);
    if (existing) {
        return existing;
    }
    const quoteAsset = params.symbol.split("-")[1] ?? "USD";
    const userQuoteAccounts = await (0, accounts_1.ensureUserLedgerAccounts)({
        userId: params.userId,
        assetCode: quoteAsset,
        mode: params.mode,
    }, db);
    return (0, service_1.postLedgerTransaction)({
        referenceType,
        referenceId,
        description: "Release unused held quote after final buy execution",
        metadata: {
            orderId: params.orderId.toString(),
            symbol: params.symbol,
            side: params.side,
            reason: "FINAL_RESIDUAL_RELEASE",
            cumulativeFilledQty: String(params.cumulativeFilledQty),
        },
        postings: [
            {
                accountId: userQuoteAccounts.held.id,
                assetCode: userQuoteAccounts.held.assetCode,
                side: "DEBIT",
                amount: releaseAmount,
            },
            {
                accountId: userQuoteAccounts.available.id,
                assetCode: userQuoteAccounts.available.assetCode,
                side: "CREDIT",
                amount: releaseAmount,
            },
        ],
    }, db);
}
async function reconcileCumulativeFills(orderId, db = prisma_1.prisma) {
    const order = await db.order.findUnique({ where: { id: orderId } });
    if (!order) {
        throw new Error("Order not found for cumulative fill reconciliation.");
    }
    const aggregate = await db.trade.aggregate({
        _sum: { qty: true },
        where: {
            OR: [{ buyOrderId: orderId }, { sellOrderId: orderId }],
        },
    });
    const cumulativeFilledQty = aggregate._sum.qty ?? new library_1.Decimal(0);
    (0, hold_release_1.assertCumulativeFillWithinOrder)(order.qty, cumulativeFilledQty);
    const rawRemaining = toDecimalExecution(order.qty).sub(toDecimalExecution(cumulativeFilledQty));
    const remainingQty = rawRemaining.lessThan(0) ? new library_1.Decimal(0) : rawRemaining;
    return {
        orderId: order.id.toString(),
        orderQty: toDecimalExecution(order.qty).toString(),
        cumulativeFilledQty: toDecimalExecution(cumulativeFilledQty).toString(),
        remainingQty: remainingQty.toString(),
    };
}
