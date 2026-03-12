import type { Widget } from "@repo/schema/ui";
type Props = Extract<Widget, { type: "TradeHistory" }>;

const apiBase =
  process.env.API_INTERNAL_URL ||
  process.env.NEXT_PUBLIC_API_URL ||
  "http://127.0.0.1:4010";

export default async function TradeHistoryWidget({ symbol, limit }: Props) {
  const url = `${apiBase}/api/v1/market/trades?symbol=${encodeURIComponent(
    symbol
  )}&limit=${limit}`;

  const r = await fetch(url, { cache: "no-store" });
  const data = await r.json();

  return (
    <div className="border rounded p-4">
      <div className="font-semibold">Trades · {symbol}</div>
      <div className="text-sm opacity-80 mt-2">
        {(data.trades ?? []).slice(0, limit).map((t: any) => (
          <div key={t.id} className="flex justify-between py-1">
            <span>{t.price}</span>
            <span>{t.qty}</span>
            <span className="opacity-60">
              {new Date(t.createdAt).toLocaleTimeString()}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
