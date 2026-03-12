export const runtime = "nodejs";

export async function GET(_req: Request, ctx: { params: { mode: string; symbol: string } }) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const upstream = await fetch(
    `${base}/api/v1/stream/${encodeURIComponent(ctx.params.mode)}/${encodeURIComponent(ctx.params.symbol)}`,
    { headers: { Accept: "text/event-stream" } }
  );

  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  });
}
