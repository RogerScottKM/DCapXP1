export async function GET(
  _req: Request,
  ctx: { params: { mode: string; symbol: string } }
) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = `${base}/v1/stream/${encodeURIComponent(ctx.params.symbol)}?mode=${encodeURIComponent(ctx.params.mode)}`;

  const upstream = await fetch(url, {
    cache: "no-store",
    headers: { Accept: "text/event-stream" },
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
