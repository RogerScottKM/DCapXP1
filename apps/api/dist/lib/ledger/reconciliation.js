"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.assertTradeSettlementConsistency = assertTradeSettlementConsistency;
exports.reconcileTradeSettlement = reconcileTradeSettlement;
const library_1 = require("@prisma/client/runtime/library");
const prisma_1 = require("../prisma");
function readMetadataObject(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
        return {};
    }
    return value;
}
function asString(value) {
    if (value === null || value === undefined)
        return null;
    return String(value);
}
function assertDecimalEqual(actual, expected, label) {
    if (!actual.eq(expected)) {
        throw new Error(`${label} mismatch: expected ${expected.toString()}, got ${actual.toString()}`);
    }
}
function assertTradeSettlementConsistency(input) {
    const metadata = readMetadataObject(input.ledgerTransaction.metadata);
    const expectedReferenceId = `${input.trade.id.toString()}:FILL_SETTLEMENT`;
    if (input.ledgerTransaction.referenceType !== "ORDER_EVENT") {
        throw new Error("Ledger transaction referenceType must be ORDER_EVENT for fills.");
    }
    if (input.ledgerTransaction.referenceId !== expectedReferenceId) {
        throw new Error("Ledger transaction referenceId does not match trade settlement reference.");
    }
    if (asString(metadata.tradeRef) !== input.trade.id.toString()) {
        throw new Error("Ledger transaction metadata.tradeRef does not match trade id.");
    }
    if (asString(metadata.buyOrderId) !== input.trade.buyOrderId.toString()) {
        throw new Error("Ledger transaction metadata.buyOrderId does not match.");
    }
    if (asString(metadata.sellOrderId) !== input.trade.sellOrderId.toString()) {
        throw new Error("Ledger transaction metadata.sellOrderId does not match.");
    }
    if (asString(metadata.symbol) !== input.trade.symbol) {
        throw new Error("Ledger transaction metadata.symbol does not match.");
    }
    if (asString(metadata.mode) !== input.trade.mode) {
        throw new Error("Ledger transaction metadata.mode does not match.");
    }
    const metadataQty = new library_1.Decimal(asString(metadata.qty) ?? "0");
    const metadataPrice = new library_1.Decimal(asString(metadata.price) ?? "0");
    assertDecimalEqual(metadataQty, new library_1.Decimal(input.trade.qty), "Trade quantity");
    assertDecimalEqual(metadataPrice, new library_1.Decimal(input.trade.price), "Trade price");
    const postings = input.ledgerTransaction.postings ?? [];
    if (postings.length < 4) {
        throw new Error("Ledger transaction must contain postings for fill settlement.");
    }
    return {
        ok: true,
        referenceId: expectedReferenceId,
        postingCount: postings.length,
    };
}
async function reconcileTradeSettlement(tradeId, db = prisma_1.prisma) {
    const resolvedTradeId = BigInt(String(tradeId));
    const trade = await db.trade.findUnique({
        where: { id: resolvedTradeId },
    });
    if (!trade) {
        throw new Error(`Trade ${resolvedTradeId.toString()} not found.`);
    }
    const ledgerTransaction = await db.ledgerTransaction.findFirst({
        where: {
            referenceType: "ORDER_EVENT",
            referenceId: `${trade.id.toString()}:FILL_SETTLEMENT`,
        },
        include: {
            postings: true,
        },
    });
    if (!ledgerTransaction) {
        throw new Error(`Ledger settlement not found for trade ${trade.id.toString()}.`);
    }
    return assertTradeSettlementConsistency({
        trade,
        ledgerTransaction,
    });
}
