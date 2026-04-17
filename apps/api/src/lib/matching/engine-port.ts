import type { PrismaClient, Prisma } from "@prisma/client";

type LedgerDbClient = PrismaClient | Prisma.TransactionClient;

export type MatchingEngineExecutionInput = {
  orderId: bigint | string;
  quoteFeeBps?: string;
};

export type MatchingEngineExecutionResult = {
  execution: unknown;
  orderReconciliation: unknown;
  engine: string;
};

export interface MatchingEnginePort {
  readonly name: string;
  executeLimitOrder(
    input: MatchingEngineExecutionInput,
    db: LedgerDbClient,
  ): Promise<MatchingEngineExecutionResult>;
}
