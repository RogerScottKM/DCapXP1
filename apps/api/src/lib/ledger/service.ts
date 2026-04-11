import { Prisma, type PrismaClient } from "@prisma/client";

import { prisma } from "../prisma";
import { assertBalancedPostings, type PostingInput } from "./posting";

type LedgerDbClient = PrismaClient | Prisma.TransactionClient;

export type LedgerTransactionInput = {
  referenceType?: string;
  referenceId?: string;
  description?: string;
  metadata?: Prisma.InputJsonValue;
  postings: PostingInput[];
};

async function createPostedTransaction(
  db: LedgerDbClient,
  input: LedgerTransactionInput,
) {
  const postings = assertBalancedPostings(input.postings);

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

export async function postLedgerTransaction(
  input: LedgerTransactionInput,
  db: LedgerDbClient = prisma,
) {
  if ("$transaction" in db) {
    return db.$transaction((tx) => createPostedTransaction(tx as Prisma.TransactionClient, input));
  }

  return createPostedTransaction(db, input);
}
