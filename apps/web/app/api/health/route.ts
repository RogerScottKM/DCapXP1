// apps/web/src/app/api/health/route.ts
export async function GET() {
  const base = process.env.API_INTERNAL_URL ?? 'http://127.0.0.1:4010';
  const r = await fetch(`${base}/health`, { cache: 'no-store' });
  const body = await r.text();
  return new Response(body, {
    status: r.status,
    headers: { 'content-type': 'application/json' },
  });
}
