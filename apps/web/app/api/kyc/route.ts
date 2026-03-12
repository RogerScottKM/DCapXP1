export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function POST(req: Request) {
  const base = process.env.API_INTERNAL_URL ?? 'http://127.0.0.1:4010';
  const body = await req.text();
  const r = await fetch(`${base}/v1/kyc/submit`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-user': 'demo' },
    body,
  });
  return new Response(await r.text(), { status: r.status, headers: { 'content-type': 'application/json' } });
}
