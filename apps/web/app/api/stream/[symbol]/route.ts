export async function GET(
  req: Request,
  ctx: { params: { symbol: string } }
) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = new URL(req.url);
  const mode = url.searchParams.get("mode") ?? "PAPER";
  const symbol = encodeURIComponent(ctx.params.symbol);

  const upstreamUrl = `${base}/v1/stream/${symbol}?mode=${encodeURIComponent(mode)}`;

  const upstream = await fetch(upstreamUrl, {
    cache: "no-store",
    headers: {
      Accept: "text/event-stream",
    },
  });

  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      "Content-Type": upstream.headers.get("content-type") ?? "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      "Connection": "keep-alive",
      "X-Accel-Buffering": "no",
    },
  });
}
