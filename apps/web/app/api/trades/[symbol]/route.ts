import { NextResponse } from "next/server";

export async function GET(req: Request, ctx: { params: { symbol: string } }) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = new URL(req.url);

  // Keep mode for UI compatibility, but DO NOT forward it to /api/v1/market/*
  // (market routes may validate query strictly).
  const _mode = url.searchParams.get("mode") ?? "PAPER";

  const limit = url.searchParams.get("limit") ?? "60";
  const symbol = ctx.params.symbol;

  const upstream = new URL(`${base}/api/v1/market/trades`);
  upstream.searchParams.set("symbol", symbol);
  upstream.searchParams.set("limit", limit);

  const r = await fetch(upstream.toString(), { cache: "no-store" });

  const contentType = r.headers.get("content-type") ?? "";
  const raw = await r.text();

  // Defensive parsing: if upstream ever returns HTML (404 etc), return a helpful JSON payload.
  let data: any;
  if (contentType.includes("application/json")) {
    try {
      data = JSON.parse(raw);
    } catch {
      return NextResponse.json(
        {
          ok: false,
          error: "Upstream returned invalid JSON",
          upstreamUrl: upstream.toString(),
          upstreamStatus: r.status,
          upstreamContentType: contentType,
          upstreamBodyPreview: raw.slice(0, 1200),
        },
        { status: 502 }
      );
    }
  } else {
    return NextResponse.json(
      {
        ok: false,
        error: "Upstream did not return JSON",
        upstreamUrl: upstream.toString(),
        upstreamStatus: r.status,
        upstreamContentType: contentType,
        upstreamBodyPreview: raw.slice(0, 1200),
      },
      { status: 502 }
    );
  }

  // UI convenience: some components expect `items` as an alias of `trades`
  if (data && Array.isArray(data.trades) && !Array.isArray(data.items)) {
    data.items = data.trades;
  }

  return NextResponse.json(data, { status: r.status });
}
