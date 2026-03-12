export const dynamic = 'force-dynamic';
export const revalidate = 0;
export const runtime = 'nodejs';
import { NextResponse } from 'next/server';
const API = process.env.NEXT_PUBLIC_API_URL ?? 'http://127.0.0.1:4010';

export async function GET() {
  const r = await fetch(`${API}/v1/admin/kyc/pending`, { headers: { 'x-user': 'demo' }});
  const j = await r.json();
  return NextResponse.json(j, { status: r.status });
}
