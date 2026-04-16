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
migration_path = root / "apps/api/prisma/migrations/20260412_order_status_expansion/migration.sql"
order_state_path = root / "apps/api/src/lib/ledger/order-state.ts"
order_state_test_path = root / "apps/api/test/ledger.order-state.test.ts"

if not pkg_path.exists():
    raise SystemExit(f"Missing package.json: {pkg_path}")
if not schema_path.exists():
    raise SystemExit(f"Missing schema.prisma: {schema_path}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:ledger:order-state"] = "vitest run test/ledger.order-state.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

migration_sql = dedent("""\
-- Add PARTIALLY_FILLED and CANCEL_PENDING to OrderStatus enum.
-- These are safe ALTER TYPE ... ADD VALUE statements (Postgres 9.1+).
-- They cannot run inside a multi-statement transaction, so Prisma
-- must apply them one at a time.

ALTER TYPE "OrderStatus" ADD VALUE IF NOT EXISTS 'PARTIALLY_FILLED';
ALTER TYPE "OrderStatus" ADD VALUE IF NOT EXISTS 'CANCEL_PENDING';
""")
migration_path.parent.mkdir(parents=True, exist_ok=True)
migration_path.write_text(migration_sql)

schema_text = schema_path.read_text()
replacement_enum = dedent("""\
enum OrderStatus {
  OPEN
  PARTIALLY_FILLED
  FILLED
  CANCEL_PENDING
  CANCELLED
}
""")

pattern = r'enum\s+OrderStatus\s*\{[^}]*\}'
new_schema_text, count = re.subn(pattern, replacement_enum.rstrip(), schema_text, count=1, flags=re.DOTALL)
if count != 1:
    raise SystemExit("Could not patch OrderStatus enum in schema.prisma")
schema_path.write_text(new_schema_text)

order_state_ts = dedent("""\
import { Decimal } from "@prisma/client/runtime/library";

export type Decimalish = string | number | Decimal;

function toDecimal(value: Decimalish): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

// ─── Order status constants ──────────────────────────────
// Mirrors the Prisma OrderStatus enum after migration.
export const ORDER_STATUS = {
  OPEN: "OPEN",
  PARTIALLY_FILLED: "PARTIALLY_FILLED",
  FILLED: "FILLED",
  CANCEL_PENDING: "CANCEL_PENDING",
  CANCELLED: "CANCELLED",
} as const;

export type OrderStatusValue = (typeof ORDER_STATUS)[keyof typeof ORDER_STATUS];

// ─── Valid state transitions ─────────────────────────────
//
//  OPEN ─────────────► PARTIALLY_FILLED ───► FILLED
//   │                        │
//   ▼                        ▼
//  CANCEL_PENDING ──► CANCELLED (releases remaining held)
//
// FILLED and CANCELLED are terminal states.
const VALID_TRANSITIONS: Record<string, Set<string>> = {
  [ORDER_STATUS.OPEN]: new Set([
    ORDER_STATUS.PARTIALLY_FILLED,
    ORDER_STATUS.FILLED,
    ORDER_STATUS.CANCEL_PENDING,
    ORDER_STATUS.CANCELLED,
  ]),
  [ORDER_STATUS.PARTIALLY_FILLED]: new Set([
    ORDER_STATUS.PARTIALLY_FILLED, // additional fills
    ORDER_STATUS.FILLED,
    ORDER_STATUS.CANCEL_PENDING,
    ORDER_STATUS.CANCELLED,
  ]),
  [ORDER_STATUS.CANCEL_PENDING]: new Set([
    ORDER_STATUS.CANCELLED,
    // A fill can still land while cancel is pending (race condition).
    // In that case we go back to PARTIALLY_FILLED, then re-cancel.
    ORDER_STATUS.PARTIALLY_FILLED,
    ORDER_STATUS.FILLED,
  ]),
  [ORDER_STATUS.FILLED]: new Set([]),
  [ORDER_STATUS.CANCELLED]: new Set([]),
};

// ─── Qty helpers ─────────────────────────────────────────

export function computeRemainingQty(orderQty: Decimalish, executedQty: Decimalish): Decimal {
  const remaining = toDecimal(orderQty).minus(toDecimal(executedQty));
  return remaining.lessThan(0) ? new Decimal(0) : remaining;
}

export function isFullyFilled(orderQty: Decimalish, executedQty: Decimalish): boolean {
  return computeRemainingQty(orderQty, executedQty).lessThanOrEqualTo(0);
}

export function assertExecutedQtyWithinOrder(orderQty: Decimalish, executedQty: Decimalish): void {
  const order = toDecimal(orderQty);
  const executed = toDecimal(executedQty);
  if (executed.greaterThan(order)) {
    throw new Error(
      `Executed quantity exceeds order quantity: ${executed.toString()} > ${order.toString()}`,
    );
  }
}

// ─── Status derivation ───────────────────────────────────

/**
 * Derives the correct order status from current state and fill progress.
 *
 * Rules:
 *  - Terminal states (FILLED, CANCELLED) are preserved.
 *  - If fully filled → FILLED.
 *  - If partially filled (executedQty > 0 but < orderQty) → PARTIALLY_FILLED.
 *  - If no fills yet → preserve current (OPEN or CANCEL_PENDING).
 */
export function deriveOrderStatus(
  currentStatus: string,
  orderQty: Decimalish,
  executedQty: Decimalish,
): OrderStatusValue {
  // Terminal states are never changed
  if (currentStatus === ORDER_STATUS.CANCELLED) {
    return ORDER_STATUS.CANCELLED;
  }
  if (currentStatus === ORDER_STATUS.FILLED) {
    return ORDER_STATUS.FILLED;
  }

  const executed = toDecimal(executedQty);
  const order = toDecimal(orderQty);

  if (executed.greaterThanOrEqualTo(order)) {
    return ORDER_STATUS.FILLED;
  }

  if (executed.greaterThan(0)) {
    return ORDER_STATUS.PARTIALLY_FILLED;
  }

  // No fills yet — keep current state (OPEN or CANCEL_PENDING)
  if (currentStatus === ORDER_STATUS.CANCEL_PENDING) {
    return ORDER_STATUS.CANCEL_PENDING;
  }

  return ORDER_STATUS.OPEN;
}

// ─── Transition validation ───────────────────────────────

export function assertValidTransition(from: string, to: string): void {
  if (from === to) return; // no-op transitions are always valid

  const allowed = VALID_TRANSITIONS[from];
  if (!allowed || !allowed.has(to)) {
    throw new Error(
      `Invalid order status transition: ${from} → ${to}`,
    );
  }
}

/**
 * Returns true if the order can still accept fills.
 * CANCEL_PENDING can receive fills (race condition with matching engine).
 */
export function canReceiveFills(status: string): boolean {
  return (
    status === ORDER_STATUS.OPEN ||
    status === ORDER_STATUS.PARTIALLY_FILLED ||
    status === ORDER_STATUS.CANCEL_PENDING
  );
}

/**
 * Returns true if the order can be cancelled.
 */
export function canCancel(status: string): boolean {
  return (
    status === ORDER_STATUS.OPEN ||
    status === ORDER_STATUS.PARTIALLY_FILLED
  );
}
""")
order_state_path.parent.mkdir(parents=True, exist_ok=True)
order_state_path.write_text(order_state_ts)

order_state_test_ts = dedent("""\
import { Decimal } from "@prisma/client/runtime/library";
import { describe, expect, it } from "vitest";

import {
  assertExecutedQtyWithinOrder,
  assertValidTransition,
  canCancel,
  canReceiveFills,
  computeRemainingQty,
  deriveOrderStatus,
  isFullyFilled,
  ORDER_STATUS,
} from "../src/lib/ledger/order-state";

describe("order-state — qty helpers", () => {
  it("computes remaining quantity for partial fills", () => {
    expect(computeRemainingQty("10", "3.5").toString()).toBe("6.5");
    expect(isFullyFilled("10", "3.5")).toBe(false);
  });

  it("returns zero remaining for fully filled orders", () => {
    expect(computeRemainingQty("10", "10").toString()).toBe("0");
    expect(isFullyFilled("10", "10")).toBe(true);
  });

  it("clamps negative remaining to zero", () => {
    expect(computeRemainingQty("5", "6").toString()).toBe("0");
  });

  it("rejects executed qty exceeding order qty", () => {
    expect(() =>
      assertExecutedQtyWithinOrder(new Decimal("2"), new Decimal("2.1")),
    ).toThrow(/exceeds order quantity/i);
  });

  it("accepts executed qty equal to order qty", () => {
    expect(() =>
      assertExecutedQtyWithinOrder("10", "10"),
    ).not.toThrow();
  });
});

describe("order-state — deriveOrderStatus", () => {
  it("returns FILLED when fully executed", () => {
    expect(deriveOrderStatus("OPEN", "10", "10")).toBe("FILLED");
  });

  it("returns PARTIALLY_FILLED when partially executed", () => {
    expect(deriveOrderStatus("OPEN", "10", "4")).toBe("PARTIALLY_FILLED");
  });

  it("returns OPEN when no fills on an OPEN order", () => {
    expect(deriveOrderStatus("OPEN", "10", "0")).toBe("OPEN");
  });

  it("preserves CANCEL_PENDING when no fills yet", () => {
    expect(deriveOrderStatus("CANCEL_PENDING", "10", "0")).toBe("CANCEL_PENDING");
  });

  it("returns PARTIALLY_FILLED even from CANCEL_PENDING if fills landed", () => {
    expect(deriveOrderStatus("CANCEL_PENDING", "10", "3")).toBe("PARTIALLY_FILLED");
  });

  it("returns FILLED from CANCEL_PENDING if fully filled (race condition)", () => {
    expect(deriveOrderStatus("CANCEL_PENDING", "10", "10")).toBe("FILLED");
  });

  it("preserves CANCELLED as terminal", () => {
    expect(deriveOrderStatus("CANCELLED", "10", "4")).toBe("CANCELLED");
  });

  it("preserves FILLED as terminal", () => {
    expect(deriveOrderStatus("FILLED", "10", "10")).toBe("FILLED");
  });
});

describe("order-state — transition validation", () => {
  it("allows OPEN → PARTIALLY_FILLED", () => {
    expect(() => assertValidTransition("OPEN", "PARTIALLY_FILLED")).not.toThrow();
  });

  it("allows OPEN → FILLED", () => {
    expect(() => assertValidTransition("OPEN", "FILLED")).not.toThrow();
  });

  it("allows OPEN → CANCEL_PENDING", () => {
    expect(() => assertValidTransition("OPEN", "CANCEL_PENDING")).not.toThrow();
  });

  it("allows OPEN → CANCELLED", () => {
    expect(() => assertValidTransition("OPEN", "CANCELLED")).not.toThrow();
  });

  it("allows PARTIALLY_FILLED → FILLED", () => {
    expect(() => assertValidTransition("PARTIALLY_FILLED", "FILLED")).not.toThrow();
  });

  it("allows PARTIALLY_FILLED → CANCELLED", () => {
    expect(() => assertValidTransition("PARTIALLY_FILLED", "CANCELLED")).not.toThrow();
  });

  it("allows CANCEL_PENDING → CANCELLED", () => {
    expect(() => assertValidTransition("CANCEL_PENDING", "CANCELLED")).not.toThrow();
  });

  it("allows CANCEL_PENDING → PARTIALLY_FILLED (fill race)", () => {
    expect(() => assertValidTransition("CANCEL_PENDING", "PARTIALLY_FILLED")).not.toThrow();
  });

  it("rejects FILLED → anything", () => {
    expect(() => assertValidTransition("FILLED", "OPEN")).toThrow(/Invalid order status transition/);
    expect(() => assertValidTransition("FILLED", "CANCELLED")).toThrow(/Invalid order status transition/);
  });

  it("rejects CANCELLED → anything", () => {
    expect(() => assertValidTransition("CANCELLED", "OPEN")).toThrow(/Invalid order status transition/);
    expect(() => assertValidTransition("CANCELLED", "FILLED")).toThrow(/Invalid order status transition/);
  });

  it("allows no-op transitions (same state)", () => {
    expect(() => assertValidTransition("OPEN", "OPEN")).not.toThrow();
    expect(() => assertValidTransition("FILLED", "FILLED")).not.toThrow();
  });
});

describe("order-state — canReceiveFills", () => {
  it("OPEN can receive fills", () => {
    expect(canReceiveFills("OPEN")).toBe(true);
  });

  it("PARTIALLY_FILLED can receive fills", () => {
    expect(canReceiveFills("PARTIALLY_FILLED")).toBe(true);
  });

  it("CANCEL_PENDING can receive fills (race condition)", () => {
    expect(canReceiveFills("CANCEL_PENDING")).toBe(true);
  });

  it("FILLED cannot receive fills", () => {
    expect(canReceiveFills("FILLED")).toBe(false);
  });

  it("CANCELLED cannot receive fills", () => {
    expect(canReceiveFills("CANCELLED")).toBe(false);
  });
});

describe("order-state — canCancel", () => {
  it("OPEN can be cancelled", () => {
    expect(canCancel("OPEN")).toBe(true);
  });

  it("PARTIALLY_FILLED can be cancelled", () => {
    expect(canCancel("PARTIALLY_FILLED")).toBe(true);
  });

  it("FILLED cannot be cancelled", () => {
    expect(canCancel("FILLED")).toBe(false);
  });

  it("CANCELLED cannot be cancelled again", () => {
    expect(canCancel("CANCELLED")).toBe(false);
  });

  it("CANCEL_PENDING cannot be cancelled again", () => {
    expect(canCancel("CANCEL_PENDING")).toBe(false);
  });
});
""")
order_state_test_path.parent.mkdir(parents=True, exist_ok=True)
order_state_test_path.write_text(order_state_test_ts)

print("Patched package.json, wrote migration/sql + schema enum expansion, and replaced order-state files for Phase 2H.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 2H patch applied."
