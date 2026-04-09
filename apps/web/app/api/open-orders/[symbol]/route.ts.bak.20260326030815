import { NextResponse } from "next/server";

export async function GET(req: Request, ctx: { params: { symbol: string } }) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = new URL(req.url);

  const symbol = ctx.params.symbol;
  const limit = url.searchParams.get("limit") ?? "50";

  const upstream = new URL(`${base}/api/v1/market/open-orders`);
  upstream.searchParams.set("symbol", symbol);
  upstream.searchParams.set("limit", limit);

  const r = await fetch(upstream.toString(), { cache: "no-store" });
  return NextResponse.json(await r.json(), { status: r.status });
}
