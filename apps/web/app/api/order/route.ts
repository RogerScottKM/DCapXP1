export async function POST(req: Request) {
  const base = process.env.API_INTERNAL_URL ?? "http://api:4010";
  const body = await req.text();

  const r = await fetch(`${base}/v1/orders`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-user": "demo" },
    body,
  });

  const text = await r.text();
  return new Response(text, {
    status: r.status,
    headers: { "content-type": "application/json" },
  });
}
