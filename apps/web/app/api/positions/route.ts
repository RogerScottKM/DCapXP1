import { NextResponse } from "next/server";
import { cookies } from "next/headers";

async function resolveUserId(base: string): Promise<string | null> {
  const jar = cookies();
  const sess = jar.get("dcapx_session")?.value;
  if (!sess) return null;

  const r = await fetch(`${base}/api/auth/session`, {
    cache: "no-store",
    headers: {
      Cookie: `dcapx_session=${sess}`,
      Accept: "application/json",
    },
  });

  if (!r.ok) return null;

  const data = await r.json().catch(() => null);
  return data?.user?.id ?? null;
}

export async function GET(req: Request) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const url = new URL(req.url);
  const mode = url.searchParams.get("mode") ?? "PAPER";

  const userId = await resolveUserId(base);

  const upstream = new URL(`${base}/v1/market/positions`);
  upstream.searchParams.set("mode", mode);
  if (userId) upstream.searchParams.set("userId", userId);

  const r = await fetch(upstream.toString(), { cache: "no-store" });
  const raw = await r.text();

  let data: any;
  try {
    data = JSON.parse(raw);
  } catch {
    return NextResponse.json(
      {
        ok: false,
        error: "Upstream returned non-JSON for positions",
        upstreamUrl: upstream.toString(),
        upstreamStatus: r.status,
        upstreamBodyPreview: raw.slice(0, 1000),
      },
      { status: 502 }
    );
  }

  const balances = Array.isArray(data.balances) ? data.balances : [];
  return NextResponse.json(
    {
      ok: true,
      mode,
      userId,
      balances,
      positions: balances,
      items: balances,
    },
    { status: 200 }
  );
}
