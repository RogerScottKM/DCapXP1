import { Decimal } from "@prisma/client/runtime/library";
import { type PrismaClient, type Prisma } from "@prisma/client";

import { getOrderRemainingQty } from "../ledger/execution";
import type {
  MatchingEngineExecutionInput,
  MatchingEngineExecutionResult,
  MatchingEnginePort,
} from "./engine-port";
import { InMemoryOrderBook } from "./in-memory-order-book";

type LedgerDbClient = PrismaClient | Prisma.TransactionClient;

export class InMemoryMatchingEngine implements MatchingEnginePort {
  readonly name = "IN_MEMORY_MATCHER";
  private readonly books = new Map<string, InMemoryOrderBook>();

  private getBookKey(symbol: string, mode: string): string {
    return `${symbol}:${mode}`;
  }

  private getBook(symbol: string, mode: string): InMemoryOrderBook {
    const key = this.getBookKey(symbol, mode);
    let existing = this.books.get(key);
    if (!existing) {
      existing = new InMemoryOrderBook();
      this.books.set(key, existing);
    }
    return existing;
  }

  async executeLimitOrder(
    input: MatchingEngineExecutionInput,
    db: LedgerDbClient,
  ): Promise<MatchingEngineExecutionResult> {
    const order = await db.order.findUniqueOrThrow({
      where: { id: BigInt(String(input.orderId)) },
    });

    const remainingQty = await getOrderRemainingQty(order as any, db as any);
    const book = this.getBook(order.symbol, order.mode);

    const execution = book.matchIncoming({
      orderId: order.id.toString(),
      symbol: order.symbol,
      side: order.side as any,
      price: new Decimal(order.price),
      qty: remainingQty,
      timeInForce: (order as any).timeInForce ?? "GTC",
      createdAt: order.createdAt,
    });

    return {
      execution: {
        order: {
          id: order.id,
          symbol: order.symbol,
          side: order.side,
          price: order.price,
          qty: order.qty,
          status: order.status,
          mode: order.mode,
          createdAt: order.createdAt,
          timeInForce: (order as any).timeInForce ?? "GTC",
        },
        fills: execution.fills,
        remainingQty: execution.remainingQty,
        tifAction: execution.tifAction,
        restingOrderId: execution.restingOrderId,
      },
      orderReconciliation: {
        ok: true,
        engine: this.name,
        note: "Experimental in-memory engine foundation; ledger settlement is not yet integrated.",
      },
      engine: this.name,
    };
  }
}

export const inMemoryMatchingEngine = new InMemoryMatchingEngine();
