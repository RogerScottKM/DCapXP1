import { Prisma, type PrismaClient, type TradeMode } from "@prisma/client";

import { prisma } from "../prisma";
import { reserveOrderOnPlacement } from "../ledger";
import { normalizeTimeInForce } from "../ledger/time-in-force";
import { ORDER_STATUS } from "../ledger/order-state";
import type { MatchingEnginePort } from "./engine-port";
import { selectMatchingEngine } from "./select-engine";
import { buildSymbolModeKey, runSerializedByKey } from "./serialized-dispatch";
import { buildMatchingEventsFromSubmission, emitMatchingEvents } from "./matching-events";
import { enforceAdmissionControls } from "./admission-controls";

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
  preferredEngine?: string | null;
};

export async function submitLimitOrder(
  input: SubmitLimitOrderInput,
  db: PrismaClient = prisma,
  engine?: MatchingEnginePort,
) {
  const normalizedTimeInForce = normalizeTimeInForce(input.timeInForce);
  const selectedEngine = engine ?? selectMatchingEngine(input.preferredEngine as any);

  return db.$transaction(async (tx) => {
await enforceAdmissionControls({
  db: tx as any,
  userId: input.userId,
  symbol: input.symbol,
  mode: String(input.mode),
  price: input.price,
});

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

    const executeThroughSelectedEngine = () =>
      selectedEngine.executeLimitOrder(
        {
          orderId: order.id,
          quoteFeeBps: input.quoteFeeBps ?? "0",
        },
        tx,
      );

    const engineResult =
      selectedEngine.name === "IN_MEMORY_MATCHER"
        ? await runSerializedByKey(
            buildSymbolModeKey(input.symbol, String(input.mode)),
            executeThroughSelectedEngine,
          )
        : await executeThroughSelectedEngine();

    const events = buildMatchingEventsFromSubmission({
      order,
      execution: engineResult.execution,
      engine: engineResult.engine,
      source: input.source,
      timeInForce: normalizedTimeInForce,
    });
    const emittedEvents = emitMatchingEvents(events);

    return {
      order,
      ledgerReservation,
      execution: engineResult.execution,
      orderReconciliation: engineResult.orderReconciliation,
      engine: engineResult.engine,
      source: input.source,
      timeInForce: normalizedTimeInForce,
      events: emittedEvents,
    };
  });
}
