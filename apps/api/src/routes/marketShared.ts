// apps/api/src/routes/marketShared.ts
import { Decimal } from "@prisma/client/runtime/library";

export type BookLevel = 2 | 3;

export function parsePositiveInt(
  v: unknown,
  fallback: number,
  opts: { min?: number; max?: number } = {}
) {
  const min = opts.min ?? 1;
  const max = opts.max ?? 10_000;

  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;

  const x = Math.floor(n);
  if (x < min) return min;
  if (x > max) return max;
  return x;
}

export function parseBookLevel(v: unknown, fallback: BookLevel = 2): BookLevel {
  const s = String(v ?? "").trim();
  if (s === "2") return 2;
  if (s === "3") return 3;
  return fallback;
}

/**
 * Aggregates sorted L3 rows into L2 price buckets.
 * Assumes `rows` is already sorted best->worst (bids desc, asks asc).
 * Map preserves insertion order so level ordering stays correct.
 */
export function aggregateByPrice(
  rows: Array<{ price: any; qty: any }>,
  depth: number
) {
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
