// apps/web/app/api/stream/[symbol]/route.ts
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(req: Request, { params }: { params: { symbol: string } }) {
  const base =
    process.env.API_INTERNAL_URL ||
    process.env.NEXT_PUBLIC_API_URL ||
    "http://127.0.0.1:4010";

  const symbol = encodeURIComponent(params.symbol);
  const incoming = new URL(req.url);
  const qs = incoming.searchParams.toString();
  const upstream = `${base}/v1/stream/${symbol}${qs ? `?${qs}` : ""}`;

  const r = await fetch(upstream, {
    cache: "no-store",
    headers: { accept: "text/event-stream" },
  });

  const ct = r.headers.get("content-type") ?? "";

  // If upstream is SSE, stream it through.
  if (ct.includes("text/event-stream")) {
    return new Response(r.body, {
      status: r.status,
      headers: {
        "content-type": "text/event-stream",
        "cache-control": "no-cache",
        "connection": "keep-alive",
      },
    });
  }

  // Otherwise return JSON (or whatever upstream returned) faithfully.
  const buf = await r.arrayBuffer();
  return new Response(buf, {
    status: r.status,
    headers: {
      "content-type": ct || "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}
