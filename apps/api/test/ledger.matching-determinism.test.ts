import { Decimal } from "@prisma/client/runtime/library";
import { describe, expect, it } from "vitest";

import {
  buildMakerOrderByForTaker,
  compareMakerPriority,
  sortMakersForTaker,
} from "../src/lib/ledger/matching-priority";

describe("ledger matching determinism", () => {
  it("builds ascending price then ascending time for BUY takers", () => {
    expect(buildMakerOrderByForTaker("BUY")).toEqual([
      { price: "asc" },
      { createdAt: "asc" },
    ]);
  });

  it("builds descending price then ascending time for SELL takers", () => {
    expect(buildMakerOrderByForTaker("SELL")).toEqual([
      { price: "desc" },
      { createdAt: "asc" },
    ]);
  });

  it("prioritizes the lower ask for BUY takers", () => {
    const earlierHigh = { price: new Decimal("101"), createdAt: new Date("2026-01-01T00:00:00Z") };
    const laterLow = { price: new Decimal("99"), createdAt: new Date("2026-01-01T00:10:00Z") };

    expect(compareMakerPriority("BUY", laterLow, earlierHigh)).toBeLessThan(0);
  });

  it("prioritizes the higher bid for SELL takers", () => {
    const earlierLow = { price: new Decimal("99"), createdAt: new Date("2026-01-01T00:00:00Z") };
    const laterHigh = { price: new Decimal("101"), createdAt: new Date("2026-01-01T00:10:00Z") };

    expect(compareMakerPriority("SELL", laterHigh, earlierLow)).toBeLessThan(0);
  });

  it("uses earlier createdAt as the tie-breaker at equal price", () => {
    const earlier = { price: new Decimal("100"), createdAt: new Date("2026-01-01T00:00:00Z") };
    const later = { price: new Decimal("100"), createdAt: new Date("2026-01-01T00:05:00Z") };

    expect(compareMakerPriority("BUY", earlier, later)).toBeLessThan(0);
    expect(compareMakerPriority("SELL", earlier, later)).toBeLessThan(0);
  });

  it("returns 0 for exact price-time ties", () => {
    const a = { price: new Decimal("100"), createdAt: new Date("2026-01-01T00:00:00Z") };
    const b = { price: new Decimal("100"), createdAt: new Date("2026-01-01T00:00:00Z") };

    expect(compareMakerPriority("BUY", a, b)).toBe(0);
    expect(compareMakerPriority("SELL", a, b)).toBe(0);
  });

  it("sorts BUY-side maker candidates deterministically across price levels and ties", () => {
    const makers = [
      { id: "m3", price: "101", createdAt: new Date("2026-01-01T00:00:00Z") },
      { id: "m2", price: "99", createdAt: new Date("2026-01-01T00:10:00Z") },
      { id: "m1", price: "99", createdAt: new Date("2026-01-01T00:00:00Z") },
      { id: "m4", price: "100", createdAt: new Date("2026-01-01T00:00:00Z") },
    ];

    const sorted = sortMakersForTaker("BUY", makers);

    expect(sorted.map((m) => m.id)).toEqual(["m1", "m2", "m4", "m3"]);
  });

  it("sorts SELL-side maker candidates deterministically across price levels and ties", () => {
    const makers = [
      { id: "m3", price: "99", createdAt: new Date("2026-01-01T00:00:00Z") },
      { id: "m2", price: "101", createdAt: new Date("2026-01-01T00:10:00Z") },
      { id: "m1", price: "101", createdAt: new Date("2026-01-01T00:00:00Z") },
      { id: "m4", price: "100", createdAt: new Date("2026-01-01T00:00:00Z") },
    ];

    const sorted = sortMakersForTaker("SELL", makers);

    expect(sorted.map((m) => m.id)).toEqual(["m1", "m2", "m4", "m3"]);
  });
});
