import { NextRequest, NextResponse } from 'next/server';

const API = process.env.NEXT_PUBLIC_API_URL ?? 'http://127.0.0.1:4010';

export async function POST(_req: NextRequest, ctx: { params: { id: string } }) {
  const r = await fetch(`${API}/v1/orders/${encodeURIComponent(ctx.params.id)}/cancel`, {
    method: 'POST',
    headers: { 'x-user': 'demo' },
  });
  const j = await r.json();
  return NextResponse.json(j, { status: r.status });
}
