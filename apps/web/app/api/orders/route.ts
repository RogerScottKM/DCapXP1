// apps/web/app/api/orders/route.ts
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function POST(req: Request) {
  const base = process.env.API_INTERNAL_URL ?? 'http://127.0.0.1:4010';
  const body = await req.text();
  const r = await fetch(`${base}/v1/orders`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body,
  });
  // pass through whatever the API returns (already JSON)
  const text = await r.text();
  return new Response(text, {
    status: r.status,
    headers: { 'content-type': r.headers.get('content-type') ?? 'application/json' },
  });
}
