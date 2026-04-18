#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 1 && -n "${1:-}" ]]; then
  ROOT="$1"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import sys
from textwrap import dedent

root = Path(sys.argv[1])

pkg_path = root / "apps/api/package.json"
test_path = root / "apps/api/test/matching.property-invariants.test.ts"

if not pkg_path.exists():
    raise SystemExit(f"Missing required file: {pkg_path}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:matching:property-invariants"] = "vitest run test/matching.property-invariants.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(dedent("""import { beforeEach, describe, expect, it } from "vitest";

import { InMemoryOrderBook, type InMemoryBookOrder } from "../src/lib/matching/in-memory-order-book";

type Side = "BUY" | "SELL";
type Tif = "GTC" | "IOC" | "FOK" | "POST_ONLY";

type MakerSeed = {
  orderId: string;
  symbol: string;
  side: Side;
  price: number;
  remainingQty: number;
  createdAt: Date;
  timeInForce: "GTC";
};

function mulberry32(seed: number) {
  let t = seed >>> 0;
  return function (): number {
    t += 0x6d2b79f5;
    let r = Math.imul(t ^ (t >>> 15), 1 | t);
    r ^= r + Math.imul(r ^ (r >>> 7), 61 | r);
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

function randInt(rng: () => number, min: number, max: number): number {
  return Math.floor(rng() * (max - min + 1)) + min;
}

function cloneMakers(makers: MakerSeed[]): MakerSeed[] {
  return makers.map((maker) => ({
    ...maker,
    createdAt: new Date(maker.createdAt.getTime()),
  }));
}

function createBook(makers: MakerSeed[]): InMemoryOrderBook {
  const book = new InMemoryOrderBook();
  for (const maker of makers) {
    book.add({
      orderId: maker.orderId,
      symbol: maker.symbol,
      side: maker.side,
      price: String(maker.price),
      remainingQty: String(maker.remainingQty),
      createdAt: maker.createdAt,
      timeInForce: maker.timeInForce,
    });
  }
  return book;
}

function manualSortForTaker(side: Side, makers: MakerSeed[]): MakerSeed[] {
  return [...makers].sort((a, b) => {
    if (side === "BUY") {
      if (a.price !== b.price) return a.price - b.price;
      return a.createdAt.getTime() - b.createdAt.getTime();
    }
    if (a.price !== b.price) return b.price - a.price;
    return a.createdAt.getTime() - b.createdAt.getTime();
  });
}

function wouldCross(takerSide: Side, takerPrice: number, maker: MakerSeed): boolean {
  return takerSide === "BUY" ? maker.price <= takerPrice : maker.price >= takerPrice;
}

function deriveTifAction(tif: Tif, remainingQty: number, initialQty: number): "KEEP_OPEN" | "CANCEL_REMAINDER" | "FILLED" {
  if (remainingQty <= 0) return "FILLED";
  if (tif === "IOC" || tif === "FOK") return "CANCEL_REMAINDER";
  return "KEEP_OPEN";
}

function manualSpec(input: {
  makers: MakerSeed[];
  takerSide: Side;
  takerPrice: number;
  takerQty: number;
  tif: Tif;
  orderId: string;
}) {
  const makers = cloneMakers(input.makers);
  const opposite = makers.filter((maker) => maker.side !== input.takerSide);
  const sorted = manualSortForTaker(input.takerSide, opposite);
  const bestOpposite = sorted[0];

  if (input.tif === "POST_ONLY" && bestOpposite && wouldCross(input.takerSide, input.takerPrice, bestOpposite)) {
    throw new Error("POST_ONLY");
  }

  if (input.tif === "FOK") {
    const fillable = sorted
      .filter((maker) => wouldCross(input.takerSide, input.takerPrice, maker))
      .reduce((sum, maker) => sum + maker.remainingQty, 0);
    if (fillable < input.takerQty) {
      throw new Error("FOK");
    }
  }

  let remaining = input.takerQty;
  const fills: Array<{ makerOrderId: string; takerOrderId: string; qty: string; price: string }> = [];

  for (const maker of sorted) {
    if (remaining <= 0) break;
    if (!wouldCross(input.takerSide, input.takerPrice, maker)) break;
    if (maker.remainingQty <= 0) continue;

    const fillQty = Math.min(remaining, maker.remainingQty);
    maker.remainingQty -= fillQty;
    remaining -= fillQty;

    fills.push({
      makerOrderId: maker.orderId,
      takerOrderId: input.orderId,
      qty: String(fillQty),
      price: String(maker.price),
    });
  }

  const tifAction = deriveTifAction(input.tif, remaining, input.takerQty);

  return {
    fills,
    remainingQty: String(remaining),
    tifAction,
  };
}

function randomMakers(rng: () => number, side: Side, count: number): MakerSeed[] {
  const symbol = "BTC-USD";
  const baseTime = new Date("2026-01-01T00:00:00.000Z").getTime();
  const makers: MakerSeed[] = [];

  for (let i = 0; i < count; i += 1) {
    makers.push({
      orderId: `${side.toLowerCase()}-${i + 1}`,
      symbol,
      side,
      price: side === "SELL" ? randInt(rng, 95, 105) : randInt(rng, 95, 105),
      remainingQty: randInt(rng, 1, 6),
      createdAt: new Date(baseTime + i * 1000 + randInt(rng, 0, 250)),
      timeInForce: "GTC",
    });
  }

  return makers;
}

describe("matching property-style invariants", () => {
  beforeEach(() => {
    // no global mutable test state beyond local books
  });

  it("matches BUY takers against best-priced asks first across randomized books", () => {
    for (let seed = 1; seed <= 150; seed += 1) {
      const rng = mulberry32(seed);
      const asks = randomMakers(rng, "SELL", randInt(rng, 3, 8));
      const takerPrice = randInt(rng, 96, 106);
      const takerQty = randInt(rng, 1, 12);

      const expected = manualSpec({
        makers: asks,
        takerSide: "BUY",
        takerPrice,
        takerQty,
        tif: "GTC",
        orderId: `buy-${seed}`,
      });

      const book = createBook(asks);
      const actual = book.matchIncoming({
        orderId: `buy-${seed}`,
        symbol: "BTC-USD",
        side: "BUY",
        price: String(takerPrice),
        qty: String(takerQty),
        timeInForce: "GTC",
      });

      expect(actual.fills).toEqual(expected.fills);
      expect(actual.remainingQty).toBe(expected.remainingQty);
      expect(actual.tifAction).toBe(expected.tifAction);

      const totalFillQty = actual.fills.reduce((sum, fill) => sum + Number(fill.qty), 0);
      expect(totalFillQty).toBeLessThanOrEqual(takerQty);
    }
  });

  it("matches SELL takers against best-priced bids first across randomized books", () => {
    for (let seed = 151; seed <= 300; seed += 1) {
      const rng = mulberry32(seed);
      const bids = randomMakers(rng, "BUY", randInt(rng, 3, 8));
      const takerPrice = randInt(rng, 94, 104);
      const takerQty = randInt(rng, 1, 12);

      const expected = manualSpec({
        makers: bids,
        takerSide: "SELL",
        takerPrice,
        takerQty,
        tif: "GTC",
        orderId: `sell-${seed}`,
      });

      const book = createBook(bids);
      const actual = book.matchIncoming({
        orderId: `sell-${seed}`,
        symbol: "BTC-USD",
        side: "SELL",
        price: String(takerPrice),
        qty: String(takerQty),
        timeInForce: "GTC",
      });

      expect(actual.fills).toEqual(expected.fills);
      expect(actual.remainingQty).toBe(expected.remainingQty);
      expect(actual.tifAction).toBe(expected.tifAction);

      const totalFillQty = actual.fills.reduce((sum, fill) => sum + Number(fill.qty), 0);
      expect(totalFillQty).toBeLessThanOrEqual(takerQty);
    }
  });

  it("preserves TIF invariants across randomized scenarios", () => {
    const tifs: Tif[] = ["GTC", "IOC", "FOK", "POST_ONLY"];

    for (let seed = 301; seed <= 420; seed += 1) {
      const rng = mulberry32(seed);
      const side: Side = rng() > 0.5 ? "BUY" : "SELL";
      const makers = randomMakers(rng, side === "BUY" ? "SELL" : "BUY", randInt(rng, 2, 6));
      const takerPrice = randInt(rng, 96, 104);
      const takerQty = randInt(rng, 1, 10);
      const tif = tifs[randInt(rng, 0, tifs.length - 1)]!;

      const book = createBook(makers);

      let expected;
      let actual;
      let expectedError: string | null = null;
      try {
        expected = manualSpec({
          makers,
          takerSide: side,
          takerPrice,
          takerQty,
          tif,
          orderId: `ord-${seed}`,
        });
      } catch (error: any) {
        expectedError = String(error?.message ?? error);
      }

      if (expectedError) {
        expect(() =>
          book.matchIncoming({
            orderId: `ord-${seed}`,
            symbol: "BTC-USD",
            side,
            price: String(takerPrice),
            qty: String(takerQty),
            timeInForce: tif,
          }),
        ).toThrow(expectedError);
        continue;
      }

      actual = book.matchIncoming({
        orderId: `ord-${seed}`,
        symbol: "BTC-USD",
        side,
        price: String(takerPrice),
        qty: String(takerQty),
        timeInForce: tif,
      });

      expect(actual.fills).toEqual(expected!.fills);
      expect(actual.remainingQty).toBe(expected!.remainingQty);
      expect(actual.tifAction).toBe(expected!.tifAction);

      if (tif === "IOC" || tif === "FOK") {
        if (Number(actual.remainingQty) > 0) {
          expect(actual.tifAction).toBe("CANCEL_REMAINDER");
          expect(actual.restingOrderId).toBeNull();
        }
      }

      if (tif === "GTC" && Number(actual.remainingQty) > 0) {
        expect(actual.tifAction).toBe("KEEP_OPEN");
        expect(actual.restingOrderId).toBe(`ord-${seed}`);
      }
    }
  });

  it("never overfills seeded maker orders across randomized taker streams", () => {
    const rng = mulberry32(777);
    const initialMakers = [
      ...randomMakers(rng, "SELL", 6),
      ...randomMakers(rng, "BUY", 6),
    ];
    const book = createBook(initialMakers);

    const makerMaxQty = new Map(initialMakers.map((maker) => [maker.orderId, maker.remainingQty]));
    const makerFilledQty = new Map<string, number>();

    for (let i = 0; i < 60; i += 1) {
      const side: Side = rng() > 0.5 ? "BUY" : "SELL";
      const tif: Tif = ["GTC", "IOC", "FOK", "POST_ONLY"][randInt(rng, 0, 3)] as Tif;
      const price = randInt(rng, 94, 106);
      const qty = randInt(rng, 1, 7);

      try {
        const result = book.matchIncoming({
          orderId: `stream-${i}`,
          symbol: "BTC-USD",
          side,
          price: String(price),
          qty: String(qty),
          timeInForce: tif,
        });

        const takerFilled = result.fills.reduce((sum, fill) => sum + Number(fill.qty), 0);
        expect(takerFilled).toBeLessThanOrEqual(qty);

        for (const fill of result.fills) {
          const next = (makerFilledQty.get(fill.makerOrderId) ?? 0) + Number(fill.qty);
          makerFilledQty.set(fill.makerOrderId, next);
          expect(next).toBeLessThanOrEqual(makerMaxQty.get(fill.makerOrderId) ?? Number.MAX_SAFE_INTEGER);
        }
      } catch (error: any) {
        const message = String(error?.message ?? error);
        expect(message.includes("POST_ONLY") || message.includes("FOK")).toBe(true);
      }
    }

    for (const order of book.snapshot("BUY")) {
      expect(Number(order.remainingQty.toString())).toBeGreaterThanOrEqual(0);
    }
    for (const order of book.snapshot("SELL")) {
      expect(Number(order.remainingQty.toString())).toBeGreaterThanOrEqual(0);
    }
  });
});
"""))

print("Patched package.json and wrote apps/api/test/matching.property-invariants.test.ts for Phase 5D.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 5D patch applied."
