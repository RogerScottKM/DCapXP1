import type { Widget } from "@repo/schema/ui";
type Props = Extract<Widget, { type: "OrderBook" }>;

const apiBase =
  process.env.API_INTERNAL_URL ||
  process.env.NEXT_PUBLIC_API_URL ||
  "http://127.0.0.1:4010";

export default async function OrderBookWidget({ symbol, depth }: Props) {
  const url = `${apiBase}/api/v1/market/orderbook?symbol=${encodeURIComponent(
    symbol
  )}&depth=${depth}`;

  const r = await fetch(url, { cache: "no-store" });
  const data = await r.json();

  return (
    <div className="border rounded p-4">
      <div className="font-semibold">OrderBook · {symbol}</div>

      <div className="grid grid-cols-2 gap-4 mt-3 text-sm">
        <div>
          <div className="font-medium mb-1">Bids</div>
          <ul className="space-y-1">
            {(data.bids ?? []).map((x: any, i: number) => (
              <li key={i} className="flex justify-between">
                <span>{x.price}</span>
                <span>{x.qty}</span>
              </li>
            ))}
          </ul>
        </div>

        <div>
          <div className="font-medium mb-1">Asks</div>
          <ul className="space-y-1">
            {(data.asks ?? []).map((x: any, i: number) => (
              <li key={i} className="flex justify-between">
                <span>{x.price}</span>
                <span>{x.qty}</span>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
}
