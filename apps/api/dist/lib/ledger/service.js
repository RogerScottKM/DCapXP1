"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.postLedgerTransaction = postLedgerTransaction;
const prisma_1 = require("../prisma");
const posting_1 = require("./posting");
async function createPostedTransaction(db, input) {
    const postings = (0, posting_1.assertBalancedPostings)(input.postings);
    const transaction = await db.ledgerTransaction.create({
        data: {
            referenceType: input.referenceType,
            referenceId: input.referenceId,
            description: input.description,
            metadata: input.metadata,
            status: "POSTED",
        },
    });
    await db.ledgerPosting.createMany({
        data: postings.map((posting) => ({
            transactionId: transaction.id,
            accountId: posting.accountId,
            assetCode: posting.assetCode,
            side: posting.side,
            amount: posting.amount.toString(),
        })),
    });
    return db.ledgerTransaction.findUniqueOrThrow({
        where: { id: transaction.id },
        include: { postings: true },
    });
}
async function postLedgerTransaction(input, db = prisma_1.prisma) {
    if ("$transaction" in db) {
        return db.$transaction((tx) => createPostedTransaction(tx, input));
    }
    return createPostedTransaction(db, input);
}
