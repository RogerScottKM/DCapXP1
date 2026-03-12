interface Ctx { params: { id: string } }

export async function POST(_req: Request, ctx: Ctx) {
  const base = process.env.API_INTERNAL_URL ?? 'http://127.0.0.1:4010';
  const r = await fetch(`${base}/v1/orders/${ctx.params.id}/cancel`, {
    method: 'POST',
    headers: { 'x-user': 'demo' },
  });
  return new Response(await r.text(), { status: r.status, headers: { 'content-type': 'application/json' } });
}
