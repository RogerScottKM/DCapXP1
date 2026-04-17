import { Decimal } from "@prisma/client/runtime/library";
import {
  type PrismaClient,
  type Prisma,
  type Order,
} from "@prisma/client";

import {
  getOrderRemainingQty,
  releaseBuyPriceImprovement,
  reconcileOrderExecution,
  syncOrderStatusFromTrades,
} from "../ledger/execution";
import { releaseOrderOnCancel, settleMatchedTrade } from "../ledger/order-lifecycle";
import { reconcileTradeSettlement } from "../ledger/reconciliation";
import { ORDER_STATUS, assertValidTransition, deriveOrderStatus } from "../ledger/order-state";
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

    const bookExecution = book.matchIncoming({
      orderId: order.id.toString(),
      symbol: order.symbol,
      side: order.side as any,
      price: new Decimal(order.price),
      qty: remainingQty,
      timeInForce: (order as any).timeInForce ?? "GTC",
      createdAt: order.createdAt,
    });

    const settlementResults: Array<Record<string, unknown>> = [];

    for (const fill of bookExecution.fills) {
      const makerOrder = await db.order.findUniqueOrThrow({
        where: { id: BigInt(fill.makerOrderId) },
      });

      const fillQty = new Decimal(fill.qty);
      const executionPrice = new Decimal(fill.price);
      const quoteFee = new Decimal(0);

      const buyOrder = order.side === "BUY" ? order : makerOrder;
      const sellOrder = order.side === "SELL" ? order : makerOrder;

      const trade = await db.trade.create({
        data: {
          symbol: order.symbol,
          price: executionPrice,
          qty: fillQty,
          mode: order.mode,
          buyOrderId: buyOrder.id,
          sellOrderId: sellOrder.id,
        },
      });

      const ledgerSettlement = await settleMatchedTrade(
        {
          tradeRef: trade.id.toString(),
          buyOrderId: buyOrder.id,
          sellOrderId: sellOrder.id,
          symbol: order.symbol,
          qty: fillQty,
          price: executionPrice,
          mode: order.mode,
          quoteFee,
        },
        db as any,
      );

      const buyPriceImprovementRelease = await releaseBuyPriceImprovement(
        {
          tradeRef: trade.id.toString(),
          orderId: buyOrder.id,
          userId: buyOrder.userId,
          symbol: order.symbol,
          limitPrice: buyOrder.price,
          executionPrice,
          fillQty,
          mode: order.mode,
        },
        db as any,
      );

      const tradeReconciliation = await reconcileTradeSettlement(trade.id, db as any);

      await syncOrderStatusFromTrades(buyOrder.id, db as any);
      await syncOrderStatusFromTrades(sellOrder.id, db as any);

      settlementResults.push({
        trade,
        ledgerSettlement,
        buyPriceImprovementRelease,
        tradeReconciliation,
      });
    }

    let finalOrder: Order = await db.order.findUniqueOrThrow({
      where: { id: order.id },
    });

    const finalRemaining = await getOrderRemainingQty(finalOrder as any, db as any);
    const executedQty = new Decimal(order.qty).minus(finalRemaining);

    if (bookExecution.tifAction === "CANCEL_REMAINDER" && finalRemaining.greaterThan(0)) {
      await releaseOrderOnCancel(
        {
          orderId: finalOrder.id,
          userId: finalOrder.userId,
          symbol: finalOrder.symbol,
          side: finalOrder.side,
          qty: finalRemaining,
          price: finalOrder.price,
          mode: finalOrder.mode,
          reason: "CANCEL",
        },
        db as any,
      );

      const currentDerivedStatus = deriveOrderStatus(
        finalOrder.status,
        finalOrder.qty,
        executedQty,
      );
      assertValidTransition(currentDerivedStatus, ORDER_STATUS.CANCELLED);

      finalOrder = await db.order.update({
        where: { id: finalOrder.id },
        data: { status: ORDER_STATUS.CANCELLED as any },
      });
    }

    const orderReconciliation =
      settlementResults.length > 0
        ? await reconcileOrderExecution(order.id, db as any)
        : {
            orderId: order.id.toString(),
            status: finalOrder.status,
            expectedStatus: finalOrder.status,
            tradeCount: 0,
            ledgerTransactionCount: 0,
            executedQty: executedQty.toString(),
            remainingQty: finalRemaining.toString(),
          };

    return {
      execution: {
        order: {
          id: finalOrder.id,
          symbol: finalOrder.symbol,
          side: finalOrder.side,
          price: finalOrder.price,
          qty: finalOrder.qty,
          status: finalOrder.status,
          mode: finalOrder.mode,
          createdAt: finalOrder.createdAt,
          timeInForce: (finalOrder as any).timeInForce ?? "GTC",
        },
        fills: bookExecution.fills,
        remainingQty: finalRemaining.toString(),
        tifAction: bookExecution.tifAction,
        restingOrderId: bookExecution.restingOrderId,
        settlements: settlementResults,
        bookDelta: bookExecution.bookDelta,
      },
      orderReconciliation,
      engine: this.name,
    };
  }
}

export const inMemoryMatchingEngine = new InMemoryMatchingEngine();
