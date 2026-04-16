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
trade_path = root / "apps/api/src/routes/trade.ts"
test_path = root / "apps/api/test/trade.cancel.guard.test.ts"

if not pkg_path.exists():
    raise SystemExit(f"Missing package.json: {pkg_path}")
if not trade_path.exists():
    raise SystemExit(f"Missing trade.ts: {trade_path}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:routes:trade-cancel"] = "vitest run test/trade.cancel.guard.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

trade_text = trade_path.read_text()

order_state_import_pattern = re.compile(
    r'import\s*\{\s*([^}]*)\s*\}\s*from\s*"\.\./lib/ledger/order-state";'
)
match = order_state_import_pattern.search(trade_text)
if match:
    names = [n.strip() for n in match.group(1).split(",") if n.strip()]
    for required in ["canCancel", "ORDER_STATUS"]:
        if required not in names:
            names.append(required)
    replacement = 'import { ' + ', '.join(names) + ' } from "../lib/ledger/order-state";'
    trade_text = order_state_import_pattern.sub(replacement, trade_text, count=1)
else:
    ledger_import_anchor = 'import { enforceMandate, bumpOrdersPlaced } from "../middleware/ibac";'
    if ledger_import_anchor not in trade_text:
        raise SystemExit("Could not locate insertion point for order-state import in trade.ts")
    trade_text = trade_text.replace(
        ledger_import_anchor,
        'import { canCancel, ORDER_STATUS } from "../lib/ledger/order-state";\n' + ledger_import_anchor,
        1,
    )

old_cancel_guard = '''    const remainingQty = await getOrderRemainingQty(order, prisma);
    if (remainingQty.lessThanOrEqualTo(0) || order.status !== "OPEN") {
      return res.status(409).json({ error: "Only OPEN orders with remaining quantity can be cancelled" });
    }'''

new_cancel_guard = '''    const remainingQty = await getOrderRemainingQty(order, prisma);

    if (!canCancel(order.status)) {
      return res.status(409).json({
        error: `Cannot cancel order in status ${order.status}.`,
      });
    }

    if (remainingQty.lessThanOrEqualTo(0)) {
      return res.status(409).json({ error: "Order has no remaining quantity to cancel." });
    }'''

if old_cancel_guard in trade_text:
    trade_text = trade_text.replace(old_cancel_guard, new_cancel_guard, 1)
else:
    if 'if (!canCancel(order.status)) {' not in trade_text:
        raise SystemExit("Could not patch cancel guard block in trade.ts")

trade_text = trade_text.replace('data: { status: "CANCELLED" }', 'data: { status: ORDER_STATUS.CANCELLED }')

trade_path.write_text(trade_text)

test_text = dedent("""\
import { Decimal } from "@prisma/client/runtime/library";
import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  prismaMock,
  getOrderRemainingQty,
  releaseOrderOnCancel,
  reserveOrderOnPlacement,
  executeLimitOrderAgainstBook,
  reconcileOrderExecution,
  syncOrderStatusFromTrades,
  reconcileTradeSettlement,
  settleMatchedTrade,
  enforceMandate,
  bumpOrdersPlaced,
} = vi.hoisted(() => ({
  prismaMock: {
    order: { findUnique: vi.fn() },
    $transaction: vi.fn(),
  },
  getOrderRemainingQty: vi.fn(),
  releaseOrderOnCancel: vi.fn(),
  reserveOrderOnPlacement: vi.fn(),
  executeLimitOrderAgainstBook: vi.fn(),
  reconcileOrderExecution: vi.fn(),
  syncOrderStatusFromTrades: vi.fn(),
  reconcileTradeSettlement: vi.fn(),
  settleMatchedTrade: vi.fn(),
  enforceMandate: vi.fn(() => (_req: any, _res: any, next: (err?: unknown) => void) => next()),
  bumpOrdersPlaced: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/ledger", () => ({
  getOrderRemainingQty,
  releaseOrderOnCancel,
  reserveOrderOnPlacement,
  executeLimitOrderAgainstBook,
  reconcileOrderExecution,
  syncOrderStatusFromTrades,
  reconcileTradeSettlement,
  settleMatchedTrade,
}));
vi.mock("../src/middleware/ibac", () => ({
  enforceMandate,
  bumpOrdersPlaced,
}));

import router from "../src/routes/trade";

function createRes() {
  const res: any = {};
  res.status = vi.fn(() => res);
  res.json = vi.fn(() => res);
  return res;
}

function getCancelHandler() {
  const layer = (router as any).stack.find(
    (entry: any) => entry.route?.path === "/orders/:orderId/cancel",
  );
  if (!layer) {
    throw new Error("Cancel route not found");
  }
  return layer.route.stack[layer.route.stack.length - 1].handle;
}

describe("trade route cancel guard", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("allows cancelling a PARTIALLY_FILLED order with remaining quantity", async () => {
    const handler = getCancelHandler();
    const order = {
      id: 101n,
      userId: "user-1",
      status: "PARTIALLY_FILLED",
      symbol: "BTC-USD",
      side: "BUY",
      price: new Decimal("100"),
      mode: "PAPER",
    };

    prismaMock.order.findUnique.mockResolvedValue(order);
    getOrderRemainingQty.mockResolvedValue(new Decimal("6"));
    releaseOrderOnCancel.mockResolvedValue({ ok: true });

    prismaMock.$transaction.mockImplementation(async (fn: any) =>
      fn({
        order: {
          update: vi.fn().mockResolvedValue({
            ...order,
            status: "CANCELLED",
          }),
        },
      }),
    );

    const req: any = {
      params: { orderId: "101" },
      principal: { type: "AGENT", userId: "user-1" },
    };
    const res = createRes();

    await handler(req, res);

    expect(res.status).not.toHaveBeenCalledWith(409);
    expect(releaseOrderOnCancel).toHaveBeenCalled();
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        ok: true,
        remainingQty: "6",
      }),
    );
  });

  it("rejects cancelling a FILLED order", async () => {
    const handler = getCancelHandler();

    prismaMock.order.findUnique.mockResolvedValue({
      id: 102n,
      userId: "user-1",
      status: "FILLED",
      symbol: "BTC-USD",
      side: "BUY",
      price: new Decimal("100"),
      mode: "PAPER",
    });
    getOrderRemainingQty.mockResolvedValue(new Decimal("0"));

    const req: any = {
      params: { orderId: "102" },
      principal: { type: "AGENT", userId: "user-1" },
    };
    const res = createRes();

    await handler(req, res);

    expect(res.status).toHaveBeenCalledWith(409);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        error: expect.stringContaining("Cannot cancel order in status FILLED"),
      }),
    );
  });

  it("rejects cancelling a CANCEL_PENDING order", async () => {
    const handler = getCancelHandler();

    prismaMock.order.findUnique.mockResolvedValue({
      id: 103n,
      userId: "user-1",
      status: "CANCEL_PENDING",
      symbol: "BTC-USD",
      side: "BUY",
      price: new Decimal("100"),
      mode: "PAPER",
    });
    getOrderRemainingQty.mockResolvedValue(new Decimal("5"));

    const req: any = {
      params: { orderId: "103" },
      principal: { type: "AGENT", userId: "user-1" },
    };
    const res = createRes();

    await handler(req, res);

    expect(res.status).toHaveBeenCalledWith(409);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        error: expect.stringContaining("Cannot cancel order in status CANCEL_PENDING"),
      }),
    );
  });

  it("rejects cancelling an order with no remaining quantity", async () => {
    const handler = getCancelHandler();

    prismaMock.order.findUnique.mockResolvedValue({
      id: 104n,
      userId: "user-1",
      status: "PARTIALLY_FILLED",
      symbol: "BTC-USD",
      side: "BUY",
      price: new Decimal("100"),
      mode: "PAPER",
    });
    getOrderRemainingQty.mockResolvedValue(new Decimal("0"));

    const req: any = {
      params: { orderId: "104" },
      principal: { type: "AGENT", userId: "user-1" },
    };
    const res = createRes();

    await handler(req, res);

    expect(res.status).toHaveBeenCalledWith(409);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        error: "Order has no remaining quantity to cancel.",
      }),
    );
  });
});
""")

test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(test_text)

print("Patched package.json, updated trade.ts cancel semantics, and wrote apps/api/test/trade.cancel.guard.test.ts for Phase 2I.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 2I patch applied."
