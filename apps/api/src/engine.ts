import { EventEmitter } from "node:events";
type Side = "BUY" | "SELL";
type Decimal = string; // keep as strings, DB stores precise decimals

export interface BookLevel { price: Decimal; qty: Decimal; }
export interface OrderInBook {
  id: bigint; userId: string; side: Side;
  price: Decimal; remaining: Decimal; createdAt: number;
}
const cmp = (a: number, b: number) => (a < b ? -1 : a > b ? 1 : 0);

// very small in-memory book per market (price-time priority)
export class OrderBook extends EventEmitter {
  bids: OrderInBook[] = []; // sorted desc price, then time asc
  asks: OrderInBook[] = []; // sorted asc price, then time asc

  snapshot() {
    const top = (arr: OrderInBook[]) => {
      if (!arr.length) return { price: "0", qty: "0" };
      const p = arr[0].price;
      const qty = arr.filter(x => x.price === p).reduce((s, x) => (BigInt(s) + BigInt(x.remaining)).toString(), "0");
      return { price: p, qty };
    };
    return { bid: top(this.bids), ask: top(this.asks) };
  }

  private sortBooks() {
    this.bids.sort((a,b) => cmp(Number(b.price), Number(a.price)) || cmp(a.createdAt, b.createdAt));
    this.asks.sort((a,b) => cmp(Number(a.price), Number(b.price)) || cmp(a.createdAt, b.createdAt));
  }

  place(o: OrderInBook) {
    const trades: { price: Decimal; qty: Decimal; buyId: bigint; sellId: bigint }[] = [];
    if (o.side === "BUY") {
      while (this.asks.length && Number(o.remaining) > 0 && Number(o.price) >= Number(this.asks[0].price)) {
        const best = this.asks[0];
        const fillQty = String(Math.min(Number(o.remaining), Number(best.remaining)));
        trades.push({ price: best.price, qty: fillQty, buyId: o.id, sellId: best.id });
        best.remaining = String(Number(best.remaining) - Number(fillQty));
        o.remaining = String(Number(o.remaining) - Number(fillQty));
        if (Number(best.remaining) === 0) this.asks.shift();
      }
      if (Number(o.remaining) > 0) { this.bids.push(o); this.sortBooks(); }
    } else {
      while (this.bids.length && Number(o.remaining) > 0 && Number(o.price) <= Number(this.bids[0].price)) {
        const best = this.bids[0];
        const fillQty = String(Math.min(Number(o.remaining), Number(best.remaining)));
        trades.push({ price: best.price, qty: fillQty, buyId: best.id, sellId: o.id });
        best.remaining = String(Number(best.remaining) - Number(fillQty));
        o.remaining = String(Number(o.remaining) - Number(fillQty));
        if (Number(best.remaining) === 0) this.bids.shift();
      }
      if (Number(o.remaining) > 0) { this.asks.push(o); this.sortBooks(); }
    }
    if (trades.length) this.emit("trades", trades);
    this.emit("book", this.snapshot());
    return trades;
  }
}
