#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import re
import sys

root = Path(sys.argv[1])

# 1) package.json: add order-state test script
pkg_path = root / "apps/api/package.json"
pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:ledger:order-state"] = "vitest run -- ledger.order-state.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

# 2) add ledger order-state helper
order_state_path = root / "apps/api/src/lib/ledger/order-state.ts"
order_state_path.write_text('''import { Decimal } from "@prisma/client/runtime/library";\n\nexport type Decimalish = string | number | Decimal;\n\nfunction toDecimal(value: Decimalish): Decimal {\n  return value instanceof Decimal ? value : new Decimal(value);\n}\n\nexport function computeRemainingQty(orderQty: Decimalish, executedQty: Decimalish): Decimal {\n  const remaining = toDecimal(orderQty).minus(toDecimal(executedQty));\n  return remaining.lessThan(0) ? new Decimal(0) : remaining;\n}\n\nexport function isFullyFilled(orderQty: Decimalish, executedQty: Decimalish): boolean {\n  return computeRemainingQty(orderQty, executedQty).lessThanOrEqualTo(0);\n}\n\nexport function assertExecutedQtyWithinOrder(orderQty: Decimalish, executedQty: Decimalish): void {\n  const order = toDecimal(orderQty);\n  const executed = toDecimal(executedQty);\n  if (executed.greaterThan(order)) {\n    throw new Error(`Executed quantity exceeds order quantity: ${executed.toString()} > ${order.toString()}`);\n  }\n}\n\nexport function deriveOrderStatus(currentStatus: string, orderQty: Decimalish, executedQty: Decimalish): string {\n  if (currentStatus === "CANCELLED") {\n    return "CANCELLED";\n  }\n  return isFullyFilled(orderQty, executedQty) ? "FILLED" : "OPEN";\n}\n''')

# 3) patch ledger index re-export
index_path = root / "apps/api/src/lib/ledger/index.ts"
index_text = index_path.read_text()
if 'export * from "./order-state";' not in index_text:
    if not index_text.endswith("\n"):
        index_text += "\n"
    index_text += '\nexport * from "./order-state";\n'
    index_path.write_text(index_text)

# 4) patch execution.ts
exec_path = root / "apps/api/src/lib/ledger/execution.ts"
text = exec_path.read_text()

old_import = 'import { ensureUserLedgerAccounts } from "./accounts";\nimport { settleMatchedTrade } from "./order-lifecycle";\nimport { reconcileTradeSettlement } from "./reconciliation";\nimport { postLedgerTransaction } from "./service";\n'
new_import = 'import { ensureUserLedgerAccounts } from "./accounts";\nimport { settleMatchedTrade } from "./order-lifecycle";\nimport { assertExecutedQtyWithinOrder, computeRemainingQty, deriveOrderStatus } from "./order-state";\nimport { reconcileTradeSettlement } from "./reconciliation";\nimport { postLedgerTransaction } from "./service";\n'
if old_import in text:
    text = text.replace(old_import, new_import)

old_get_remaining = '''export async function getOrderRemainingQty(\n  order: Pick<Order, "id" | "qty">,\n  db: LedgerDbClient = prisma,\n): Promise<Decimal> {\n  const executed = await getOrderExecutedQty(order.id, db);\n  const remaining = new Decimal(order.qty).minus(executed);\n  return remaining.lessThan(0) ? new Decimal(0) : remaining;\n}\n\nasync function syncOrderStatus(orderId: bigint, db: LedgerDbClient): Promise<Order> {\n  const order = await db.order.findUniqueOrThrow({ where: { id: orderId } });\n  const remaining = await getOrderRemainingQty(order, db);\n  return db.order.update({\n    where: { id: orderId },\n    data: {\n      status: remaining.lessThanOrEqualTo(0) ? "FILLED" : "OPEN",\n    },\n  });\n}\n'''
new_get_remaining = '''export async function getOrderRemainingQty(\n  order: Pick<Order, "id" | "qty">,\n  db: LedgerDbClient = prisma,\n): Promise<Decimal> {\n  const executed = await getOrderExecutedQty(order.id, db);\n  assertExecutedQtyWithinOrder(order.qty, executed);\n  return computeRemainingQty(order.qty, executed);\n}\n\nexport async function syncOrderStatusFromTrades(\n  orderId: bigint | string,\n  db: LedgerDbClient = prisma,\n): Promise<Order> {\n  const normalizedId = BigInt(String(orderId));\n  const order = await db.order.findUniqueOrThrow({ where: { id: normalizedId } });\n  const executed = await getOrderExecutedQty(order.id, db);\n  assertExecutedQtyWithinOrder(order.qty, executed);\n\n  return db.order.update({\n    where: { id: order.id },\n    data: {\n      status: deriveOrderStatus(order.status, order.qty, executed) as Order["status"],\n    },\n  });\n}\n'''
if old_get_remaining in text:
    text = text.replace(old_get_remaining, new_get_remaining)

text = text.replace('    await syncOrderStatus(buyOrder.id, db);\n    await syncOrderStatus(sellOrder.id, db);\n', '    await syncOrderStatusFromTrades(buyOrder.id, db);\n    await syncOrderStatusFromTrades(sellOrder.id, db);\n')

old_reconcile_tail = '''  const executedQty = trades.reduce((acc, trade) => acc.plus(new Decimal(trade.qty)), new Decimal(0));\n  const remainingQty = new Decimal(order.qty).minus(executedQty);\n  const safeRemaining = remainingQty.lessThan(0) ? new Decimal(0) : remainingQty;\n\n  if (ledgerTransactions.length !== trades.length) {\n    throw new Error("Trade to ledger transaction count mismatch for order reconciliation.");\n  }\n\n  return {\n    orderId: String(order.id),\n    status: order.status,\n    tradeCount: trades.length,\n    ledgerTransactionCount: ledgerTransactions.length,\n    executedQty: executedQty.toString(),\n    remainingQty: safeRemaining.toString(),\n  };\n}\n'''
new_reconcile_tail = '''  const executedQty = trades.reduce((acc, trade) => acc.plus(new Decimal(trade.qty)), new Decimal(0));\n  assertExecutedQtyWithinOrder(order.qty, executedQty);\n  const safeRemaining = computeRemainingQty(order.qty, executedQty);\n\n  if (ledgerTransactions.length !== trades.length) {\n    throw new Error("Trade to ledger transaction count mismatch for order reconciliation.");\n  }\n\n  const expectedStatus = deriveOrderStatus(order.status, order.qty, executedQty);\n  if (order.status !== expectedStatus) {\n    throw new Error(`Order status mismatch: expected ${expectedStatus}, got ${order.status}`);\n  }\n\n  return {\n    orderId: String(order.id),\n    status: order.status,\n    expectedStatus,\n    tradeCount: trades.length,\n    ledgerTransactionCount: ledgerTransactions.length,\n    executedQty: executedQty.toString(),\n    remainingQty: safeRemaining.toString(),\n  };\n}\n'''
if old_reconcile_tail in text:
    text = text.replace(old_reconcile_tail, new_reconcile_tail)

exec_path.write_text(text)

# 5) patch trade.ts demo fill route to sync order status instead of forcing FILLED
trade_path = root / "apps/api/src/routes/trade.ts"
trade_text = trade_path.read_text()
trade_text = trade_text.replace(
    '  reconcileOrderExecution,\n',
    '  reconcileOrderExecution,\n  syncOrderStatusFromTrades,\n'
)
old_fill_block = '''      await tx.order.updateMany({\n        where: {\n          id: { in: [buyOrder.id, sellOrder.id] },\n        },\n        data: {\n          status: "FILLED",\n        },\n      });\n\n      const reconciliation = await reconcileTradeSettlement(trade.id, tx);\n      const buyOrderReconciliation = await reconcileOrderExecution(buyOrder.id, tx);\n      const sellOrderReconciliation = await reconcileOrderExecution(sellOrder.id, tx);\n\n      return { trade, ledgerSettlement, reconciliation, buyOrderReconciliation, sellOrderReconciliation };\n'''
new_fill_block = '''      const updatedBuyOrder = await syncOrderStatusFromTrades(buyOrder.id, tx);\n      const updatedSellOrder = await syncOrderStatusFromTrades(sellOrder.id, tx);\n\n      const reconciliation = await reconcileTradeSettlement(trade.id, tx);\n      const buyOrderReconciliation = await reconcileOrderExecution(updatedBuyOrder.id, tx);\n      const sellOrderReconciliation = await reconcileOrderExecution(updatedSellOrder.id, tx);\n\n      return {\n        trade,\n        ledgerSettlement,\n        reconciliation,\n        buyOrder: updatedBuyOrder,\n        sellOrder: updatedSellOrder,\n        buyOrderReconciliation,\n        sellOrderReconciliation,\n      };\n'''
if old_fill_block in trade_text:
    trade_text = trade_text.replace(old_fill_block, new_fill_block)
trade_path.write_text(trade_text)

# 6) add test
state_test_path = root / "apps/api/test/ledger.order-state.test.ts"
state_test_path.write_text('''import { Decimal } from "@prisma/client/runtime/library";\nimport { describe, expect, it } from "vitest";\n\nimport {\n  assertExecutedQtyWithinOrder,\n  computeRemainingQty,\n  deriveOrderStatus,\n  isFullyFilled,\n} from "../src/lib/ledger/order-state";\n\ndescribe("ledger order-state helper", () => {\n  it("computes remaining quantity for partial fills", () => {\n    const remaining = computeRemainingQty("10", "3.5");\n    expect(remaining.toString()).toBe("6.5");\n    expect(isFullyFilled("10", "3.5")).toBe(false);\n  });\n\n  it("derives OPEN for partially filled open orders and FILLED for complete fills", () => {\n    expect(deriveOrderStatus("OPEN", "10", "4")).toBe("OPEN");\n    expect(deriveOrderStatus("OPEN", "10", "10")).toBe("FILLED");\n  });\n\n  it("preserves CANCELLED and rejects overfills", () => {\n    expect(deriveOrderStatus("CANCELLED", "10", "4")).toBe("CANCELLED");\n    expect(() => assertExecutedQtyWithinOrder(new Decimal("2"), new Decimal("2.1"))).toThrow(/exceeds order quantity/i);\n  });\n});\n''')

print("Patched package.json, added order-state helper/test, re-exported order-state, and fixed partial-fill status handling for Phase 2E.")
PY

echo "Phase 2E patch applied."
