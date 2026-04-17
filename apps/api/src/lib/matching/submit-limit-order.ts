import { Prisma, type PrismaClient, type TradeMode } from "@prisma/client";

import { prisma } from "../prisma";
import { reserveOrderOnPlacement } from "../ledger";
import { normalizeTimeInForce } from "../ledger/time-in-force";
import { ORDER_STATUS } from "../ledger/order-state";
import { dbMatchingEngine } from "./db-matching-engine";
import { selectMatchingEngine } from "./select-engine";
import type { MatchingEnginePort } from "./engine-port";

export type SubmitLimitOrderInput = {
  userId: string;
  symbol: string;
  side: "BUY" | "SELL";
  price: string;
  qty: string;
  mode: TradeMode;
  quoteFeeBps?: string;
  timeInForce?: string;
  source: "HUMAN" | "AGENT";
};

export async function submitLimitOrder(
  input: SubmitLimitOrderInput,
  db: PrismaClient = prisma,
  engine?: MatchingEnginePort,
) {
  const normalizedTimeInForce = normalizeTimeInForce(input.timeInForce);
  const selectedEngine = engine ?? selectMatchingEngine();

  return db.$transaction(async (tx) => {
    const order = await tx.order.create({
      data: {
        symbol: input.symbol,
        side: input.side,
        price: new Prisma.Decimal(input.price),
        qty: new Prisma.Decimal(input.qty),
        status: ORDER_STATUS.OPEN,
        timeInForce: normalizedTimeInForce as any,
        mode: input.mode,
        userId: input.userId,
      },
    });

    const ledgerReservation = await reserveOrderOnPlacement(
      {
        orderId: order.id,
        userId: input.userId,
        symbol: input.symbol,
        side: input.side,
        qty: input.qty,
        price: input.price,
        mode: input.mode,
      },
      tx,
    );

    const engineResult = await selectedEngine.executeLimitOrder(
      {
        orderId: order.id,
        quoteFeeBps: input.quoteFeeBps ?? "0",
      },
      tx,
    );

    return {
      order,
      ledgerReservation,
      execution: engineResult.execution,
      orderReconciliation: engineResult.orderReconciliation,
      engine: engineResult.engine,
      source: input.source,
      timeInForce: normalizedTimeInForce,
    };
  });
}
