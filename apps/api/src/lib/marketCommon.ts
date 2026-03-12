// apps/api/src/lib/marketCommon.ts
import { Decimal } from "@prisma/client/runtime/library";

export type Level = 2 | 3;

export function parsePositiveInt(
  v: unknown,
  fallback: number,
  opts?: { min?: number; max?: number }
) {
  const min = opts?.min ?? 1;
  const max = opts?.max ?? 10_000;

  const n = Number(v);
  const x = Number.isFinite(n) ? Math.floor(n) : fallback;

  if (!Number.isFinite(x)) return fallback;
  if (x < min) return min;
  if (x > max) return max;
  return x;
}

export function parseLevel(v: unknown): Level {
  const s = String(v ?? "").trim();
  return s === "3" ? 3 : 2; // default L2
}

export function aggregateByPrice(rows: Array<{ price: any; qty: any }>, depth: number) {
  // insertion order preserved; relies on DB sorting (price + time)
  const m = new Map<string, Decimal>();

  for (const r of rows) {
    const p = r.price?.toString?.() ?? String(r.price);
    const q = new Decimal(r.qty?.toString?.() ?? String(r.qty));
    const cur = m.get(p);
    m.set(p, cur ? cur.add(q) : q);
  }

  const out: Array<{ price: string; qty: string }> = [];
  for (const [price, qty] of m.entries()) {
    out.push({ price, qty: qty.toString() });
    if (out.length >= depth) break;
  }
  return out;
}
