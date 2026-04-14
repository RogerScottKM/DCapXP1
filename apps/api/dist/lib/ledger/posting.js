"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.toDecimal = toDecimal;
exports.normalizePostings = normalizePostings;
exports.assertBalancedPostings = assertBalancedPostings;
exports.buildLedgerTransfer = buildLedgerTransfer;
const library_1 = require("@prisma/client/runtime/library");
function toDecimal(value) {
    return value instanceof library_1.Decimal ? value : new library_1.Decimal(value);
}
function normalizePostings(postings) {
    return postings.map((posting) => {
        const accountId = String(posting.accountId ?? "").trim();
        const assetCode = String(posting.assetCode ?? "").trim().toUpperCase();
        const side = posting.side === "CREDIT" ? "CREDIT" : "DEBIT";
        const amount = toDecimal(posting.amount);
        if (!accountId) {
            throw new Error("Ledger posting accountId is required.");
        }
        if (!assetCode) {
            throw new Error("Ledger posting assetCode is required.");
        }
        if (amount.lte(0)) {
            throw new Error("Ledger posting amount must be greater than zero.");
        }
        return { accountId, assetCode, side, amount };
    });
}
function assertBalancedPostings(postings) {
    if (postings.length < 2) {
        throw new Error("Ledger transaction must include at least two postings.");
    }
    const normalized = normalizePostings(postings);
    const grouped = new Map();
    for (const posting of normalized) {
        const current = grouped.get(posting.assetCode) ?? {
            debit: new library_1.Decimal(0),
            credit: new library_1.Decimal(0),
        };
        if (posting.side === "DEBIT") {
            current.debit = current.debit.plus(posting.amount);
        }
        else {
            current.credit = current.credit.plus(posting.amount);
        }
        grouped.set(posting.assetCode, current);
    }
    for (const [assetCode, totals] of grouped.entries()) {
        if (!totals.debit.eq(totals.credit)) {
            throw new Error(`Ledger postings are not balanced for asset ${assetCode}.`);
        }
    }
    return normalized;
}
function buildLedgerTransfer(params) {
    const amount = toDecimal(params.amount);
    if (amount.lte(0)) {
        throw new Error("Ledger transfer amount must be greater than zero.");
    }
    return [
        {
            accountId: params.fromAccountId,
            assetCode: params.assetCode,
            side: "CREDIT",
            amount,
        },
        {
            accountId: params.toAccountId,
            assetCode: params.assetCode,
            side: "DEBIT",
            amount,
        },
    ];
}
