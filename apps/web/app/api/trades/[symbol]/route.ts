import { NextResponse } from "next/server";

export async function GET(req: Request, ctx: { params: { symbol: string } }) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = new URL(req.url);

  const symbol = ctx.params.symbol;
  const limit = url.searchParams.get("limit") ?? "50";
  const mode = url.searchParams.get("mode") ?? "PAPER";

  const upstream = new URL(`${base}/v1/market/trades`);
  upstream.searchParams.set("symbol", symbol);
  upstream.searchParams.set("limit", limit);
  upstream.searchParams.set("mode", mode);

  const r = await fetch(upstream.toString(), { cache: "no-store" });
  const raw = await r.text();

  let data: any;
  try {
    data = JSON.parse(raw);
  } catch {
    return NextResponse.json(
      {
        ok: false,
        error: "Upstream returned non-JSON for trades",
        upstreamUrl: upstream.toString(),
        upstreamStatus: r.status,
        upstreamBodyPreview: raw.slice(0, 1000),
      },
      { status: 502 }
    );
  }

  const trades = Array.isArray(data.trades) ? data.trades : [];
  return NextResponse.json(
    {
      ok: true,
      symbol,
      mode,
      trades,
      items: trades,
      limit: Number(limit),
    },
    { status: 200 }
  );
}
