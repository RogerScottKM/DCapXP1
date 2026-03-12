export const runtime = 'nodejs';

export async function GET() {
  const base = process.env.API_INTERNAL_URL ?? 'http://127.0.0.1:4010';
  const r = await fetch(`${base}/v1/markets`, { cache: 'no-store' });
  const buf = await r.text();
  return new Response(buf, {
    status: r.status,
    headers: { 'content-type': 'application/json' },
  });
}
