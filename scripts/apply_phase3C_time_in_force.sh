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
import re
import sys
from textwrap import dedent

root = Path(sys.argv[1])

pkg_path = root / "apps/api/package.json"
schema_path = root / "apps/api/prisma/schema.prisma"
migration_path = root / "apps/api/prisma/migrations/20260416_phase3c_time_in_force/migration.sql"
helper_path = root / "apps/api/src/lib/ledger/time-in-force.ts"
orders_path = root / "apps/api/src/routes/orders.ts"
test_path = root / "apps/api/test/time-in-force.lib.test.ts"

for p in [pkg_path, schema_path, orders_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:lib:time-in-force"] = "vitest run test/time-in-force.lib.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

schema_text = schema_path.read_text()
if "enum TimeInForce {" not in schema_text:
    schema_text = schema_text.rstrip() + "\n\n" + dedent('''enum TimeInForce {
  GTC
  IOC
  FOK
  POST_ONLY
}
''')

order_pattern = re.compile(r'model\s+Order\s*\{.*?\n\}', re.DOTALL)
match = order_pattern.search(schema_text)
if not match:
    raise SystemExit("Could not locate model Order in schema.prisma")

order_block = match.group(0)
if "timeInForce" not in order_block:
    new_order_block = order_block[:-1].rstrip() + '\n  timeInForce TimeInForce @default(GTC)\n}'
    schema_text = schema_text.replace(order_block, new_order_block, 1)

schema_path.write_text(schema_text)

migration_sql = dedent('''-- Phase 3C: add TimeInForce enum and Order.timeInForce column.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'TimeInForce') THEN
    CREATE TYPE "TimeInForce" AS ENUM ('GTC', 'IOC', 'FOK', 'POST_ONLY');
  END IF;
END $$;

ALTER TABLE "Order"
  ADD COLUMN IF NOT EXISTS "timeInForce" "TimeInForce" NOT NULL DEFAULT 'GTC';
''')
migration_path.parent.mkdir(parents=True, exist_ok=True)
migration_path.write_text(migration_sql)

helper_ts = dedent('''import { Decimal } from "@prisma/client/runtime/library";

export type Decimalish = string | number | Decimal;

function toDecimal(value: Decimalish): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

export const ORDER_TIF = {
  GTC: "GTC",
  IOC: "IOC",
  FOK: "FOK",
  POST_ONLY: "POST_ONLY",
} as const;

export type TimeInForceValue = (typeof ORDER_TIF)[keyof typeof ORDER_TIF];

export function normalizeTimeInForce(value?: string | null): TimeInForceValue {
  const normalized = String(value ?? "GTC").trim().toUpperCase();
  if (normalized === ORDER_TIF.IOC) return ORDER_TIF.IOC;
  if (normalized === ORDER_TIF.FOK) return ORDER_TIF.FOK;
  if (normalized === ORDER_TIF.POST_ONLY) return ORDER_TIF.POST_ONLY;
  return ORDER_TIF.GTC;
}

export function wouldLimitOrderCrossBestQuote(
  side: "BUY" | "SELL",
  limitPrice: Decimalish,
  bestOppositePrice: Decimalish | null | undefined,
): boolean {
  if (bestOppositePrice === null || bestOppositePrice === undefined) return false;

  const limit = toDecimal(limitPrice);
  const opposite = toDecimal(bestOppositePrice);

  return side === "BUY"
    ? opposite.lessThanOrEqualTo(limit)
    : opposite.greaterThanOrEqualTo(limit);
}

export function assertPostOnlyWouldRest(
  side: "BUY" | "SELL",
  limitPrice: Decimalish,
  bestOppositePrice: Decimalish | null | undefined,
): void {
  if (wouldLimitOrderCrossBestQuote(side, limitPrice, bestOppositePrice)) {
    throw new Error("POST_ONLY order would cross the book.");
  }
}

export function assertFokCanFullyFill(orderQty: Decimalish, fillableQty: Decimalish): void {
  const order = toDecimal(orderQty);
  const fillable = toDecimal(fillableQty);
  if (fillable.lessThan(order)) {
    throw new Error("FOK order cannot be fully filled.");
  }
}

export function deriveTifRestingAction(
  timeInForce: string,
  executedQty: Decimalish,
  orderQty: Decimalish,
): "KEEP_OPEN" | "CANCEL_REMAINDER" | "FILLED" {
  const tif = normalizeTimeInForce(timeInForce);
  const executed = toDecimal(executedQty);
  const order = toDecimal(orderQty);

  if (executed.greaterThanOrEqualTo(order)) {
    return "FILLED";
  }

  if (tif === ORDER_TIF.IOC || tif === ORDER_TIF.FOK) {
    return "CANCEL_REMAINDER";
  }

  return "KEEP_OPEN";
}
''')
helper_path.parent.mkdir(parents=True, exist_ok=True)
helper_path.write_text(helper_ts)

orders_text = orders_path.read_text()

if 'import { normalizeTimeInForce } from "../lib/ledger/time-in-force";' not in orders_text:
    import_anchor = 'import { canCancel, ORDER_STATUS } from "../lib/ledger/order-state";'
    if import_anchor not in orders_text:
        raise SystemExit("Could not find order-state import anchor in orders.ts")
    orders_text = orders_text.replace(
        import_anchor,
        import_anchor + '\nimport { normalizeTimeInForce } from "../lib/ledger/time-in-force";',
        1,
    )

schema_anchor = '  quoteFeeBps: z.string().optional().default("0"),'
schema_add = '  timeInForce: z.enum(["GTC", "IOC", "FOK", "POST_ONLY"]).optional().default("GTC"),'
if schema_anchor in orders_text and schema_add not in orders_text:
    orders_text = orders_text.replace(schema_anchor, schema_anchor + '\n' + schema_add, 1)

parse_anchor = '      const payload = placeOrderSchema.parse(req.body);\n'
if 'const normalizedTimeInForce = normalizeTimeInForce(payload.timeInForce);' not in orders_text:
    if parse_anchor not in orders_text:
        raise SystemExit("Could not find payload parse anchor in orders.ts")
    orders_text = orders_text.replace(
        parse_anchor,
        parse_anchor + '      const normalizedTimeInForce = normalizeTimeInForce(payload.timeInForce);\n',
        1,
    )

create_anchor = '            status: "OPEN",\n            mode: payload.mode as TradeMode,'
if create_anchor in orders_text and 'timeInForce: normalizedTimeInForce as any,' not in orders_text:
    orders_text = orders_text.replace(
        create_anchor,
        '            status: "OPEN",\n            timeInForce: normalizedTimeInForce as any,\n            mode: payload.mode as TradeMode,',
        1,
    )

if 'timeInForce: o.timeInForce,' not in orders_text:
    orders_text = orders_text.replace(
        '        status: o.status,\n        mode: o.mode,',
        '        status: o.status,\n        mode: o.mode,\n        timeInForce: o.timeInForce,',
    )
    orders_text = orders_text.replace(
        '            status: execution.order.status,\n            mode: execution.order.mode,',
        '            status: execution.order.status,\n            mode: execution.order.mode,\n            timeInForce: execution.order.timeInForce ?? normalizedTimeInForce,',
    )
    orders_text = orders_text.replace(
        '        status: order.status,\n        mode: order.mode,',
        '        status: order.status,\n        mode: order.mode,\n        timeInForce: order.timeInForce,',
    )
    orders_text = orders_text.replace(
        '          status: result.order.status,\n          mode: result.order.mode,',
        '          status: result.order.status,\n          mode: result.order.mode,\n          timeInForce: result.order.timeInForce,',
    )

orders_path.write_text(orders_text)

test_ts = dedent('''import { describe, expect, it } from "vitest";

import {
  ORDER_TIF,
  assertFokCanFullyFill,
  assertPostOnlyWouldRest,
  deriveTifRestingAction,
  normalizeTimeInForce,
  wouldLimitOrderCrossBestQuote,
} from "../src/lib/ledger/time-in-force";

describe("time-in-force helper", () => {
  it("defaults to GTC when the value is missing", () => {
    expect(normalizeTimeInForce(undefined)).toBe(ORDER_TIF.GTC);
  });

  it("normalizes IOC, FOK, and POST_ONLY values", () => {
    expect(normalizeTimeInForce("ioc")).toBe(ORDER_TIF.IOC);
    expect(normalizeTimeInForce("FOK")).toBe(ORDER_TIF.FOK);
    expect(normalizeTimeInForce("post_only")).toBe(ORDER_TIF.POST_ONLY);
  });

  it("detects when a buy order would cross the best ask", () => {
    expect(wouldLimitOrderCrossBestQuote("BUY", "100", "99")).toBe(true);
    expect(wouldLimitOrderCrossBestQuote("BUY", "100", "101")).toBe(false);
  });

  it("detects when a sell order would cross the best bid", () => {
    expect(wouldLimitOrderCrossBestQuote("SELL", "100", "101")).toBe(true);
    expect(wouldLimitOrderCrossBestQuote("SELL", "100", "99")).toBe(false);
  });

  it("rejects POST_ONLY orders that would cross", () => {
    expect(() => assertPostOnlyWouldRest("BUY", "100", "99")).toThrow(/POST_ONLY/i);
  });

  it("allows POST_ONLY orders that would rest", () => {
    expect(() => assertPostOnlyWouldRest("BUY", "100", "101")).not.toThrow();
  });

  it("rejects FOK orders that cannot be fully filled", () => {
    expect(() => assertFokCanFullyFill("10", "6")).toThrow(/FOK/i);
  });

  it("accepts FOK orders that can be fully filled", () => {
    expect(() => assertFokCanFullyFill("10", "10")).not.toThrow();
  });

  it("keeps GTC orders open when partially executed", () => {
    expect(deriveTifRestingAction("GTC", "4", "10")).toBe("KEEP_OPEN");
  });

  it("cancels IOC remainder after a partial execution", () => {
    expect(deriveTifRestingAction("IOC", "4", "10")).toBe("CANCEL_REMAINDER");
  });

  it("marks fully executed IOC orders as filled", () => {
    expect(deriveTifRestingAction("IOC", "10", "10")).toBe("FILLED");
  });
});
''')
test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(test_ts)

print("Patched package.json, added TimeInForce schema/migration + helper, patched orders.ts to accept/persist TIF, and wrote apps/api/test/time-in-force.lib.test.ts for Phase 3C.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 3C patch applied."
