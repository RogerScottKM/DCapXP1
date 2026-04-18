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
exec_path = root / "apps/api/src/lib/ledger/execution.ts"
helper_path = root / "apps/api/src/lib/ledger/matching-priority.ts"
index_path = root / "apps/api/src/lib/ledger/index.ts"
test_path = root / "apps/api/test/ledger.matching-determinism.test.ts"

for p in [pkg_path, exec_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:ledger:matching-determinism"] = "vitest run test/ledger.matching-determinism.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

helper_ts = dedent('''\
import { Decimal } from "@prisma/client/runtime/library";
import { type OrderSide } from "@prisma/client";

type Decimalish = string | number | Decimal;

export type PrioritySortableMaker = {
  price: Decimalish;
  createdAt: Date | string | number;
};

function toDecimal(value: Decimalish): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

function toTimestamp(value: Date | string | number): number {
  if (value instanceof Date) return value.getTime();
  return new Date(value).getTime();
}

export function buildMakerOrderByForTaker(side: OrderSide) {
  return side === "BUY"
    ? [{ price: "asc" as const }, { createdAt: "asc" as const }]
    : [{ price: "desc" as const }, { createdAt: "asc" as const }];
}

export function compareMakerPriority(
  takerSide: OrderSide,
  a: PrioritySortableMaker,
  b: PrioritySortableMaker,
): number {
  const priceA = toDecimal(a.price);
  const priceB = toDecimal(b.price);

  if (!priceA.eq(priceB)) {
    if (takerSide === "BUY") {
      return priceA.lessThan(priceB) ? -1 : 1;
    }
    return priceA.greaterThan(priceB) ? -1 : 1;
  }

  const tsA = toTimestamp(a.createdAt);
  const tsB = toTimestamp(b.createdAt);

  if (tsA < tsB) return -1;
  if (tsA > tsB) return 1;
  return 0;
}

export function sortMakersForTaker<T extends PrioritySortableMaker>(
  takerSide: OrderSide,
  makers: T[],
): T[] {
  return [...makers].sort((a, b) => compareMakerPriority(takerSide, a, b));
}
''')
helper_path.parent.mkdir(parents=True, exist_ok=True)
helper_path.write_text(helper_ts)

exec_text = exec_path.read_text()

if 'import { buildMakerOrderByForTaker } from "./matching-priority";' not in exec_text:
    service_import = 'import { postLedgerTransaction } from "./service";'
    if service_import not in exec_text:
        raise SystemExit("Could not find service import anchor in execution.ts")
    exec_text = exec_text.replace(
        service_import,
        service_import + '\nimport { buildMakerOrderByForTaker } from "./matching-priority";',
        1,
    )

inline_orderby = """    orderBy:
      order.side === \"BUY\"
        ? [{ price: \"asc\" }, { createdAt: \"asc\" }]
        : [{ price: \"desc\" }, { createdAt: \"asc\" }],"""
if inline_orderby in exec_text:
    exec_text = exec_text.replace(
        inline_orderby,
        '    orderBy: buildMakerOrderByForTaker(order.side),',
        1,
    )
elif 'orderBy: buildMakerOrderByForTaker(order.side),' not in exec_text:
    raise SystemExit("Could not patch getMatchingOrders orderBy in execution.ts")

exec_path.write_text(exec_text)

if index_path.exists():
    index_text = index_path.read_text()
    if 'export * from "./matching-priority";' not in index_text:
        index_text = index_text.rstrip() + '\nexport * from "./matching-priority";\n'
        index_path.write_text(index_text)

test_ts = dedent('''\
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
''')
test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(test_ts)

print("Patched package.json, centralized maker price-time ordering in matching-priority.ts, wired execution.ts to use it, and wrote apps/api/test/ledger.matching-determinism.test.ts for Phase 3D.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 3D patch applied."
