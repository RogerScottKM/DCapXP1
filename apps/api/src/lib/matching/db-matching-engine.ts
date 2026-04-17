import type { PrismaClient, Prisma } from "@prisma/client";

import { executeLimitOrderAgainstBook, reconcileOrderExecution } from "../ledger";
import type {
  MatchingEngineExecutionInput,
  MatchingEngineExecutionResult,
  MatchingEnginePort,
} from "./engine-port";

type LedgerDbClient = PrismaClient | Prisma.TransactionClient;

export class DbMatchingEngine implements MatchingEnginePort {
  readonly name = "DB_MATCHER";

  async executeLimitOrder(
    input: MatchingEngineExecutionInput,
    db: LedgerDbClient,
  ): Promise<MatchingEngineExecutionResult> {
    const execution = await executeLimitOrderAgainstBook(
      {
        orderId: input.orderId,
        quoteFeeBps: input.quoteFeeBps ?? "0",
      },
      db,
    );

    const orderReconciliation = await reconcileOrderExecution(input.orderId, db);

    return {
      execution,
      orderReconciliation,
      engine: this.name,
    };
  }
}

export const dbMatchingEngine = new DbMatchingEngine();
