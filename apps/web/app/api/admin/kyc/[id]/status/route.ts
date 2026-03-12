import { NextRequest, NextResponse } from 'next/server';
const API = process.env.NEXT_PUBLIC_API_URL ?? 'http://127.0.0.1:4010';

export async function PATCH(req: NextRequest, ctx: { params: { id: string } }) {
  const body = await req.text();
  const r = await fetch(`${API}/v1/admin/kyc/${encodeURIComponent(ctx.params.id)}/status`, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json', 'x-user': 'demo' },
    body,
  });
  const j = await r.json();
  return NextResponse.json(j, { status: r.status });
}
