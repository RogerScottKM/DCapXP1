"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.reserveOrderOnPlacement = reserveOrderOnPlacement;
exports.releaseOrderOnCancel = releaseOrderOnCancel;
exports.settleMatchedTrade = settleMatchedTrade;
const library_1 = require("@prisma/client/runtime/library");
const prisma_1 = require("../prisma");
const accounts_1 = require("./accounts");
const service_1 = require("./service");
function toDecimal(value) {
    return value instanceof library_1.Decimal ? value : new library_1.Decimal(value);
}
async function findMarket(symbol, db) {
    const market = await db.market.findUnique({ where: { symbol } });
    if (!market) {
        throw new Error(`Market not found for symbol ${symbol}`);
    }
    return market;
}
async function getLedgerBalance(accountId, db) {
    const postings = await db.ledgerPosting.findMany({
        where: { accountId },
        select: { side: true, amount: true },
    });
    return postings.reduce((acc, posting) => {
        const amount = new library_1.Decimal(posting.amount);
        return posting.side === "DEBIT" ? acc.minus(amount) : acc.plus(amount);
    }, new library_1.Decimal(0));
}
async function assertAccountHasBalance(accountId, required, db, label) {
    const balance = await getLedgerBalance(accountId, db);
    if (balance.lt(required)) {
        throw new Error(`${label} balance is insufficient for ledger movement.`);
    }
}
async function findExistingReference(referenceType, referenceId, db) {
    return db.ledgerTransaction.findFirst({
        where: { referenceType, referenceId },
        include: { postings: true },
    });
}
async function reserveOrderOnPlacement(input, db = prisma_1.prisma) {
    const referenceType = "ORDER_EVENT";
    const referenceId = `${String(input.orderId)}:PLACE_HOLD`;
    const existing = await findExistingReference(referenceType, referenceId, db);
    if (existing) {
        return existing;
    }
    const market = await findMarket(input.symbol, db);
    const qty = toDecimal(input.qty);
    const price = toDecimal(input.price);
    if (qty.lte(0) || price.lte(0)) {
        throw new Error("Order quantity and price must be greater than zero.");
    }
    const assetCode = input.side === "BUY" ? market.quoteAsset : market.baseAsset;
    const holdAmount = input.side === "BUY" ? qty.mul(price) : qty;
    const userAccounts = await (0, accounts_1.ensureUserLedgerAccounts)({ userId: input.userId, assetCode, mode: input.mode }, db);
    await assertAccountHasBalance(userAccounts.available.id, holdAmount, db, "Available");
    return (0, service_1.postLedgerTransaction)({
        referenceType,
        referenceId,
        description: `Reserve ${assetCode} for ${input.side} order ${String(input.orderId)}`,
        metadata: {
            event: "ORDER_PLACE_HOLD",
            orderId: String(input.orderId),
            symbol: input.symbol,
            side: input.side,
            userId: input.userId,
            mode: input.mode,
            holdAsset: assetCode,
            holdAmount: holdAmount.toString(),
        },
        postings: [
            { accountId: userAccounts.available.id, assetCode, side: "DEBIT", amount: holdAmount },
            { accountId: userAccounts.held.id, assetCode, side: "CREDIT", amount: holdAmount },
        ],
    }, db);
}
async function releaseOrderOnCancel(input, db = prisma_1.prisma) {
    const referenceType = "ORDER_EVENT";
    const referenceId = `${String(input.orderId)}:${input.reason ?? "CANCEL"}_RELEASE`;
    const existing = await findExistingReference(referenceType, referenceId, db);
    if (existing) {
        return existing;
    }
    const market = await findMarket(input.symbol, db);
    const qty = toDecimal(input.qty);
    const price = toDecimal(input.price);
    const assetCode = input.side === "BUY" ? market.quoteAsset : market.baseAsset;
    const releaseAmount = input.side === "BUY" ? qty.mul(price) : qty;
    const userAccounts = await (0, accounts_1.ensureUserLedgerAccounts)({ userId: input.userId, assetCode, mode: input.mode }, db);
    await assertAccountHasBalance(userAccounts.held.id, releaseAmount, db, "Held");
    return (0, service_1.postLedgerTransaction)({
        referenceType,
        referenceId,
        description: `Release ${assetCode} hold for order ${String(input.orderId)}`,
        metadata: {
            event: "ORDER_CANCEL_RELEASE",
            orderId: String(input.orderId),
            symbol: input.symbol,
            side: input.side,
            userId: input.userId,
            mode: input.mode,
            releaseAsset: assetCode,
            releaseAmount: releaseAmount.toString(),
            reason: input.reason ?? "CANCEL",
        },
        postings: [
            { accountId: userAccounts.held.id, assetCode, side: "DEBIT", amount: releaseAmount },
            { accountId: userAccounts.available.id, assetCode, side: "CREDIT", amount: releaseAmount },
        ],
    }, db);
}
async function settleMatchedTrade(input, db = prisma_1.prisma) {
    const referenceType = "ORDER_EVENT";
    const referenceId = `${input.tradeRef}:FILL_SETTLEMENT`;
    const existing = await findExistingReference(referenceType, referenceId, db);
    if (existing) {
        return existing;
    }
    const market = await findMarket(input.symbol, db);
    const buyOrder = await db.order.findUnique({ where: { id: BigInt(String(input.buyOrderId)) } });
    const sellOrder = await db.order.findUnique({ where: { id: BigInt(String(input.sellOrderId)) } });
    if (!buyOrder || !sellOrder) {
        throw new Error("Both buy and sell orders are required for fill settlement.");
    }
    const qty = toDecimal(input.qty);
    const price = toDecimal(input.price);
    const grossQuote = qty.mul(price);
    const quoteFee = toDecimal(input.quoteFee ?? 0);
    if (quoteFee.lt(0)) {
        throw new Error("quoteFee cannot be negative.");
    }
    if (quoteFee.greaterThan(grossQuote)) {
        throw new Error("quoteFee cannot exceed gross quote amount.");
    }
    const buyerBase = await (0, accounts_1.ensureUserLedgerAccounts)({ userId: buyOrder.userId, assetCode: market.baseAsset, mode: input.mode }, db);
    const buyerQuote = await (0, accounts_1.ensureUserLedgerAccounts)({ userId: buyOrder.userId, assetCode: market.quoteAsset, mode: input.mode }, db);
    const sellerBase = await (0, accounts_1.ensureUserLedgerAccounts)({ userId: sellOrder.userId, assetCode: market.baseAsset, mode: input.mode }, db);
    const sellerQuote = await (0, accounts_1.ensureUserLedgerAccounts)({ userId: sellOrder.userId, assetCode: market.quoteAsset, mode: input.mode }, db);
    const quoteSystem = await (0, accounts_1.ensureSystemLedgerAccounts)({ assetCode: market.quoteAsset, mode: input.mode }, db);
    await assertAccountHasBalance(buyerQuote.held.id, grossQuote, db, "Buyer held quote");
    await assertAccountHasBalance(sellerBase.held.id, qty, db, "Seller held base");
    return (0, service_1.postLedgerTransaction)({
        referenceType,
        referenceId,
        description: `Settle matched trade ${input.tradeRef}`,
        metadata: {
            event: "ORDER_FILL_SETTLEMENT",
            tradeRef: input.tradeRef,
            buyOrderId: String(input.buyOrderId),
            sellOrderId: String(input.sellOrderId),
            symbol: input.symbol,
            qty: qty.toString(),
            price: price.toString(),
            grossQuote: grossQuote.toString(),
            quoteFee: quoteFee.toString(),
            mode: input.mode,
        },
        postings: [
            { accountId: buyerQuote.held.id, assetCode: market.quoteAsset, side: "DEBIT", amount: grossQuote },
            { accountId: sellerQuote.available.id, assetCode: market.quoteAsset, side: "CREDIT", amount: grossQuote.minus(quoteFee) },
            ...(quoteFee.gt(0)
                ? [{ accountId: quoteSystem.feeRevenue.id, assetCode: market.quoteAsset, side: "CREDIT", amount: quoteFee }]
                : []),
            { accountId: sellerBase.held.id, assetCode: market.baseAsset, side: "DEBIT", amount: qty },
            { accountId: buyerBase.available.id, assetCode: market.baseAsset, side: "CREDIT", amount: qty },
        ],
    }, db);
}
