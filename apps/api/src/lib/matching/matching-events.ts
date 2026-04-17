import { Decimal } from "@prisma/client/runtime/library";

type MatchingEventType =
  | "ORDER_ACCEPTED"
  | "ORDER_FILL"
  | "ORDER_PARTIALLY_FILLED"
  | "ORDER_FILLED"
  | "ORDER_RESTED"
  | "ORDER_CANCELLED"
  | "BOOK_DELTA"
  | "RUNTIME_STATUS"
  | "RECONCILIATION_RESULT";

export type MatchingEvent = {
  type: MatchingEventType;
  ts: string;
  symbol: string;
  mode: string;
  engine: string;
  source: "HUMAN" | "AGENT" | "SYSTEM";
  payload: Record<string, unknown>;
};

export type MatchingEventEnvelope = MatchingEvent & {
  id: number;
};

type MatchingEventListener = (event: MatchingEventEnvelope) => void;

const matchingEvents: MatchingEventEnvelope[] = [];
const listeners = new Set<MatchingEventListener>();
let nextEventId = 1;

function isZeroLike(value: unknown): boolean {
  if (value === null || value === undefined) return false;
  try {
    return new Decimal(String(value)).eq(0);
  } catch {
    return false;
  }
}

function normalizeFillPayload(fill: any): Record<string, unknown> {
  if (fill?.trade) {
    return {
      tradeId: String(fill.trade.id),
      qty: String(fill.trade.qty),
      price: String(fill.trade.price),
      buyOrderId: fill.trade.buyOrderId != null ? String(fill.trade.buyOrderId) : undefined,
      sellOrderId: fill.trade.sellOrderId != null ? String(fill.trade.sellOrderId) : undefined,
    };
  }

  return {
    makerOrderId: fill?.makerOrderId != null ? String(fill.makerOrderId) : undefined,
    takerOrderId: fill?.takerOrderId != null ? String(fill.takerOrderId) : undefined,
    qty: fill?.qty != null ? String(fill.qty) : undefined,
    price: fill?.price != null ? String(fill.price) : undefined,
  };
}

export function emitMatchingEvent(event: MatchingEvent): MatchingEventEnvelope {
  const envelope: MatchingEventEnvelope = {
    ...event,
    id: nextEventId++,
  };
  matchingEvents.push(envelope);
  for (const listener of listeners) {
    try {
      listener(envelope);
    } catch {
      // listener failures must not break event publication
    }
  }
  return envelope;
}

export function emitMatchingEvents(events: MatchingEvent[]): MatchingEventEnvelope[] {
  return events.map((event) => emitMatchingEvent(event));
}

export function listMatchingEvents(limit = 100): MatchingEventEnvelope[] {
  return matchingEvents.slice(-limit);
}

export function getMatchingEventCount(): number {
  return matchingEvents.length;
}

export function subscribeMatchingEvents(listener: MatchingEventListener): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function getMatchingEventListenerCount(): number {
  return listeners.size;
}

export function resetMatchingEventsForTests(): void {
  matchingEvents.length = 0;
  listeners.clear();
  nextEventId = 1;
}

export function buildMatchingEventsFromSubmission(input: {
  order: any;
  execution: any;
  engine: string;
  source: "HUMAN" | "AGENT";
  timeInForce: string;
}): MatchingEvent[] {
  const ts = new Date().toISOString();
  const order = input.order;
  const execution = input.execution ?? {};
  const events: MatchingEvent[] = [
    {
      type: "ORDER_ACCEPTED",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: {
        orderId: String(order.id),
        side: String(order.side),
        price: String(order.price),
        qty: String(order.qty),
        timeInForce: input.timeInForce,
      },
    },
  ];

  const fills = Array.isArray(execution.fills) ? execution.fills : [];
  for (const fill of fills) {
    events.push({
      type: "ORDER_FILL",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: normalizeFillPayload(fill),
    });
  }

  if (fills.length > 0) {
    events.push({
      type: isZeroLike(execution.remainingQty) ? "ORDER_FILLED" : "ORDER_PARTIALLY_FILLED",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: {
        orderId: String(order.id),
        remainingQty: execution.remainingQty != null ? String(execution.remainingQty) : undefined,
        fillCount: fills.length,
      },
    });
  }

  if (execution.restingOrderId) {
    events.push({
      type: "ORDER_RESTED",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: {
        orderId: String(execution.restingOrderId),
        remainingQty: execution.remainingQty != null ? String(execution.remainingQty) : undefined,
      },
    });
  }

  if (execution.tifAction === "CANCEL_REMAINDER" || String(execution.order?.status ?? order.status) === "CANCELLED") {
    events.push({
      type: "ORDER_CANCELLED",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: {
        orderId: String(order.id),
        remainingQty: execution.remainingQty != null ? String(execution.remainingQty) : undefined,
        reason: execution.tifAction === "CANCEL_REMAINDER" ? "TIF_CANCEL_REMAINDER" : "CANCELLED",
      },
    });
  }

  if (execution.bookDelta) {
    events.push({
      type: "BOOK_DELTA",
      ts,
      symbol: String(order.symbol),
      mode: String(order.mode),
      engine: input.engine,
      source: input.source,
      payload: execution.bookDelta,
    });
  }

  return events;
}
