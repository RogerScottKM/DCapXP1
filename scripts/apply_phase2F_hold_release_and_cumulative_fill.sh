#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import sys

root = Path(sys.argv[1])

def read(path: Path) -> str:
    if not path.exists():
        raise SystemExit(f"Missing file: {path}")
    return path.read_text()

def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)

pkg_path = root / "apps/api/package.json"
pkg = json.loads(read(pkg_path))
scripts = pkg.setdefault("scripts", {})
scripts.setdefault("test:ledger:hold-release", "vitest run -- ledger.hold-release.test.ts")
write(pkg_path, json.dumps(pkg, indent=2) + "\n")

hold_release = '''import { Decimal } from "@prisma/client/runtime/library";

function toDecimal(value: string | number | Decimal): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

export function computeExecutedQuote(
  executedQty: string | number | Decimal,
  executionPrice: string | number | Decimal,
): Decimal {
  return toDecimal(executedQty).mul(toDecimal(executionPrice));
}

export function computeReservedQuote(
  orderQty: string | number | Decimal,
  limitPrice: string | number | Decimal,
): Decimal {
  return toDecimal(orderQty).mul(toDecimal(limitPrice));
}

export function computeRemainingQty(
  orderQty: string | number | Decimal,
  cumulativeFilledQty: string | number | Decimal,
): Decimal {
  const remaining = toDecimal(orderQty).sub(toDecimal(cumulativeFilledQty));
  return remaining.lessThan(0) ? new Decimal(0) : remaining;
}

export function assertCumulativeFillWithinOrder(
  orderQty: string | number | Decimal,
  cumulativeFilledQty: string | number | Decimal,
): void {
  if (toDecimal(cumulativeFilledQty).greaterThan(toDecimal(orderQty))) {
    throw new Error("Cumulative filled quantity cannot exceed order quantity.");
  }
}

export function computeBuyHeldQuoteRelease(params: {
  orderQty: string | number | Decimal;
  limitPrice: string | number | Decimal;
  cumulativeFilledQty: string | number | Decimal;
  weightedExecutedQuote: string | number | Decimal;
}): Decimal {
  const reserved = computeReservedQuote(params.orderQty, params.limitPrice);
  const remainingReserved = computeReservedQuote(
    computeRemainingQty(params.orderQty, params.cumulativeFilledQty),
    params.limitPrice,
  );
  const spent = toDecimal(params.weightedExecutedQuote);
  const release = reserved.sub(remainingReserved).sub(spent);
  return release.lessThan(0) ? new Decimal(0) : release;
}
'''
write(root / "apps/api/src/lib/ledger/hold-release.ts", hold_release)

idx_path = root / "apps/api/src/lib/ledger/index.ts"
idx = read(idx_path)
if 'export * from "./hold-release";' not in idx:
    idx = idx.rstrip() + '\n\nexport * from "./hold-release";\n'
write(idx_path, idx)

exec_path = root / "apps/api/src/lib/ledger/execution.ts"
exec_src = read(exec_path)
if "releaseResidualHoldAfterExecution" not in exec_src:
    exec_src += '''

import { Prisma, TradeMode } from "@prisma/client";
import { Decimal } from "@prisma/client/runtime/library";
import { computeBuyHeldQuoteRelease, assertCumulativeFillWithinOrder } from "./hold-release";
import { postLedgerTransaction } from "./service";

function toDecimalExecution(value: string | number | Decimal): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

export async function releaseResidualHoldAfterExecution(params: {
  orderId: bigint;
  userId: string;
  symbol: string;
  side: "BUY" | "SELL";
  mode: TradeMode;
  orderQty: string | number | Decimal;
  limitPrice: string | number | Decimal;
  cumulativeFilledQty: string | number | Decimal;
  weightedExecutedQuote?: string | number | Decimal;
}, tx: Prisma.TransactionClient) {
  if (params.side !== "BUY") return null;

  const releaseAmount = computeBuyHeldQuoteRelease({
    orderQty: params.orderQty,
    limitPrice: params.limitPrice,
    cumulativeFilledQty: params.cumulativeFilledQty,
    weightedExecutedQuote: params.weightedExecutedQuote ?? "0",
  });

  if (releaseAmount.lessThanOrEqualTo(0)) return null;

  return postLedgerTransaction({
    assetCode: "USD",
    referenceType: "ORDER_RELEASE",
    referenceId: `${params.orderId}:FINAL_RESIDUAL_RELEASE`,
    description: "Release unused held quote after final buy execution",
    metadata: {
      orderId: params.orderId.toString(),
      symbol: params.symbol,
      side: params.side,
      reason: "FINAL_RESIDUAL_RELEASE",
    },
    postings: [
      { ownerType: "USER", ownerRef: params.userId, accountType: "USER_HELD", side: "DEBIT", amount: releaseAmount },
      { ownerType: "USER", ownerRef: params.userId, accountType: "USER_AVAILABLE", side: "CREDIT", amount: releaseAmount },
    ],
  }, tx);
}

export async function reconcileCumulativeFills(orderId: bigint, tx: Prisma.TransactionClient) {
  const order = await tx.order.findUnique({ where: { id: orderId } });
  if (!order) throw new Error("Order not found for cumulative fill reconciliation.");

  const aggregate = await tx.trade.aggregate({
    _sum: { qty: true },
    where: { OR: [{ buyOrderId: orderId }, { sellOrderId: orderId }] },
  });

  const cumulativeFilledQty = aggregate._sum.qty ?? new Decimal(0);
  assertCumulativeFillWithinOrder(order.qty, cumulativeFilledQty);

  return {
    orderId: order.id.toString(),
    orderQty: toDecimalExecution(order.qty).toString(),
    cumulativeFilledQty: toDecimalExecution(cumulativeFilledQty).toString(),
    remainingQty: toDecimalExecution(order.qty).sub(toDecimalExecution(cumulativeFilledQty)).max(new Decimal(0)).toString(),
  };
}
'''
write(exec_path, exec_src)

trade_path = root / "apps/api/src/routes/trade.ts"
trade = read(trade_path)

if "releaseResidualHoldAfterExecution" not in trade:
    trade = trade.replace(
        "  reconcileOrderExecution,",
        "  reconcileOrderExecution,\n  releaseResidualHoldAfterExecution,\n  reconcileCumulativeFills,"
    )

if "cumulativeFillCheck" not in trade:
    trade = trade.replace(
        "      const orderReconciliation = await reconcileOrderExecution(order.id, tx);\n      return { order, ledgerReservation, execution, orderReconciliation };",
        "      const orderReconciliation = await reconcileOrderExecution(order.id, tx);\n      const cumulativeFillCheck = await reconcileCumulativeFills(order.id, tx);\n      return { order, ledgerReservation, execution, orderReconciliation, cumulativeFillCheck };"
    )

if "buyHeldRelease" not in trade:
    old = "      const updatedBuyOrder = await syncOrderStatusFromTrades(buyOrder.id, tx);\n      const updatedSellOrder = await syncOrderStatusFromTrades(sellOrder.id, tx);\n      const reconciliation = await reconcileTradeSettlement(trade.id, tx);\n      const buyOrderReconciliation = await reconcileOrderExecution(updatedBuyOrder.id, tx);\n      const sellOrderReconciliation = await reconcileOrderExecution(updatedSellOrder.id, tx);\n      return { trade, ledgerSettlement, reconciliation, buyOrder: updatedBuyOrder, sellOrder: updatedSellOrder, buyOrderReconciliation, sellOrderReconciliation, };"
    new = "      const updatedBuyOrder = await syncOrderStatusFromTrades(buyOrder.id, tx);\n      const updatedSellOrder = await syncOrderStatusFromTrades(sellOrder.id, tx);\n      const buyFillCheck = await reconcileCumulativeFills(updatedBuyOrder.id, tx);\n      const sellFillCheck = await reconcileCumulativeFills(updatedSellOrder.id, tx);\n      const buyHeldRelease = updatedBuyOrder.status === \"FILLED\"\n        ? await releaseResidualHoldAfterExecution({\n            orderId: updatedBuyOrder.id,\n            userId: updatedBuyOrder.userId,\n            symbol: updatedBuyOrder.symbol,\n            side: updatedBuyOrder.side,\n            mode: updatedBuyOrder.mode,\n            orderQty: updatedBuyOrder.qty,\n            limitPrice: updatedBuyOrder.price,\n            cumulativeFilledQty: buyFillCheck.cumulativeFilledQty,\n            weightedExecutedQuote: new Prisma.Decimal(payload.qty).mul(new Prisma.Decimal(payload.price!)),\n          }, tx)\n        : null;\n      const reconciliation = await reconcileTradeSettlement(trade.id, tx);\n      const buyOrderReconciliation = await reconcileOrderExecution(updatedBuyOrder.id, tx);\n      const sellOrderReconciliation = await reconcileOrderExecution(updatedSellOrder.id, tx);\n      return { trade, ledgerSettlement, reconciliation, buyOrder: updatedBuyOrder, sellOrder: updatedSellOrder, buyOrderReconciliation, sellOrderReconciliation, buyFillCheck, sellFillCheck, buyHeldRelease };"
    trade = trade.replace(old, new)

write(trade_path, trade)

test_src = '''import { describe, expect, it } from "vitest";
import { Decimal } from "@prisma/client/runtime/library";
import {
  computeBuyHeldQuoteRelease,
  computeExecutedQuote,
  assertCumulativeFillWithinOrder,
  computeRemainingQty,
} from "../src/lib/ledger/hold-release";

describe("ledger hold-release helpers", () => {
  it("computes residual buy hold release on final completion", () => {
    const spent = computeExecutedQuote("10", "99");
    const release = computeBuyHeldQuoteRelease({
      orderQty: "10",
      limitPrice: "100",
      cumulativeFilledQty: "10",
      weightedExecutedQuote: spent,
    });
    expect(release.toString()).toBe("10");
  });

  it("returns zero release when order still has remaining quantity", () => {
    const spent = computeExecutedQuote("4", "99");
    const release = computeBuyHeldQuoteRelease({
      orderQty: "10",
      limitPrice: "100",
      cumulativeFilledQty: "4",
      weightedExecutedQuote: spent,
    });
    expect(release.toString()).toBe("0");
    expect(computeRemainingQty("10", "4").toString()).toBe("6");
  });

  it("guards cumulative fills from exceeding order quantity", () => {
    expect(() => assertCumulativeFillWithinOrder(new Decimal("10"), new Decimal("11"))).toThrow(/cannot exceed/i);
  });
});
'''
write(root / "apps/api/test/ledger.hold-release.test.ts", test_src)

print("Patched package.json, added hold-release helper/test, re-exported hold-release, and tightened cumulative fill/release handling for Phase 2F.")
PY

echo "Phase 2F patch applied."
