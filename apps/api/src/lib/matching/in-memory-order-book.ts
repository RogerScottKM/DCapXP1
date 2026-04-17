import { Decimal } from "@prisma/client/runtime/library";
import { type OrderSide } from "@prisma/client";

import { sortMakersForTaker } from "../ledger/matching-priority";
import { deriveTifRestingAction, normalizeTimeInForce } from "../ledger/time-in-force";

type Decimalish = string | number | Decimal;

function toDecimal(value: Decimalish): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

function minDecimal(a: Decimal, b: Decimal): Decimal {
  return a.lessThanOrEqualTo(b) ? a : b;
}

export type InMemoryBookOrder = {
  orderId: string;
  symbol: string;
  side: OrderSide;
  price: Decimal;
  remainingQty: Decimal;
  createdAt: Date;
  timeInForce: string;
};

export type InMemoryFill = {
  makerOrderId: string;
  takerOrderId: string;
  qty: string;
  price: string;
};

export class InMemoryOrderBook {
  private readonly bids: InMemoryBookOrder[] = [];
  private readonly asks: InMemoryBookOrder[] = [];

  add(order: Omit<InMemoryBookOrder, "price" | "remainingQty" | "createdAt"> & {
    price: Decimalish;
    remainingQty: Decimalish;
    createdAt?: Date | string | number;
  }): InMemoryBookOrder {
    const normalized: InMemoryBookOrder = {
      ...order,
      price: toDecimal(order.price),
      remainingQty: toDecimal(order.remainingQty),
      createdAt: order.createdAt instanceof Date ? order.createdAt : new Date(order.createdAt ?? Date.now()),
    };
    const side = normalized.side === "BUY" ? this.bids : this.asks;
    side.push(normalized);
    return normalized;
  }

  remove(orderId: string): boolean {
    const before = this.bids.length + this.asks.length;
    const nextBids = this.bids.filter((o) => o.orderId !== orderId);
    const nextAsks = this.asks.filter((o) => o.orderId !== orderId);
    this.bids.splice(0, this.bids.length, ...nextBids);
    this.asks.splice(0, this.asks.length, ...nextAsks);
    return before !== this.bids.length + this.asks.length;
  }

  snapshot(side: OrderSide): InMemoryBookOrder[] {
    const source = side === "BUY" ? this.bids : this.asks;
    return source.map((o) => ({ ...o }));
  }

  matchIncoming(input: {
    orderId: string;
    symbol: string;
    side: OrderSide;
    price: Decimalish;
    qty: Decimalish;
    timeInForce?: string;
    createdAt?: Date | string | number;
  }): {
    fills: InMemoryFill[];
    remainingQty: string;
    tifAction: "KEEP_OPEN" | "CANCEL_REMAINDER" | "FILLED";
    restingOrderId: string | null;
  } {
    const tif = normalizeTimeInForce(input.timeInForce);
    const takerPrice = toDecimal(input.price);
    let remaining = toDecimal(input.qty);

    const opposite = input.side === "BUY" ? this.asks : this.bids;
    const sortedOpposite = sortMakersForTaker(input.side, opposite);

    const fills: InMemoryFill[] = [];

    for (const maker of sortedOpposite) {
      if (remaining.lessThanOrEqualTo(0)) break;

      const crosses =
        input.side === "BUY"
          ? maker.price.lessThanOrEqualTo(takerPrice)
          : maker.price.greaterThanOrEqualTo(takerPrice);

      if (!crosses) break;
      if (maker.remainingQty.lessThanOrEqualTo(0)) continue;

      const fillQty = minDecimal(remaining, maker.remainingQty);
      maker.remainingQty = maker.remainingQty.minus(fillQty);
      remaining = remaining.minus(fillQty);

      fills.push({
        makerOrderId: maker.orderId,
        takerOrderId: input.orderId,
        qty: fillQty.toString(),
        price: maker.price.toString(),
      });

      if (maker.remainingQty.lessThanOrEqualTo(0)) {
        this.remove(maker.orderId);
      } else {
        const bookSide = maker.side === "BUY" ? this.bids : this.asks;
        const idx = bookSide.findIndex((o) => o.orderId === maker.orderId);
        if (idx >= 0) bookSide[idx] = maker;
      }
    }

    const executedQty = toDecimal(input.qty).minus(remaining);
    const tifAction = deriveTifRestingAction(tif, executedQty, input.qty);

    let restingOrderId: string | null = null;
    if (tifAction === "KEEP_OPEN" && remaining.greaterThan(0)) {
      const resting = this.add({
        orderId: input.orderId,
        symbol: input.symbol,
        side: input.side,
        price: takerPrice,
        remainingQty: remaining,
        createdAt: input.createdAt,
        timeInForce: tif,
      });
      restingOrderId = resting.orderId;
    }

    return {
      fills,
      remainingQty: remaining.toString(),
      tifAction,
      restingOrderId,
    };
  }
}
