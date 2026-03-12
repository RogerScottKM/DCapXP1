import { NextResponse } from "next/server";

export async function GET(req: Request) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = new URL(req.url);

  const mode = url.searchParams.get("mode") ?? "PAPER";

  const upstream = new URL(`${base}/api/v1/market/positions`);
  upstream.searchParams.set("mode", mode);

  const r = await fetch(upstream.toString(), { cache: "no-store" });
  const text = await r.text();

  return new Response(text, {
    status: r.status,
    headers: {
      "content-type": r.headers.get("content-type") ?? "application/json",
    },
  });
}
