import { Decimal } from "@prisma/client/runtime/library";
import { describe, expect, it } from "vitest";

import {
  assertExecutedQtyWithinOrder,
  computeRemainingQty,
  deriveOrderStatus,
  isFullyFilled,
} from "../src/lib/ledger/order-state";

describe("ledger order-state helper", () => {
  it("computes remaining quantity for partial fills", () => {
    const remaining = computeRemainingQty("10", "3.5");
    expect(remaining.toString()).toBe("6.5");
    expect(isFullyFilled("10", "3.5")).toBe(false);
  });

  it("derives OPEN for partially filled open orders and FILLED for complete fills", () => {
    expect(deriveOrderStatus("OPEN", "10", "4")).toBe("OPEN");
    expect(deriveOrderStatus("OPEN", "10", "10")).toBe("FILLED");
  });

  it("preserves CANCELLED and rejects overfills", () => {
    expect(deriveOrderStatus("CANCELLED", "10", "4")).toBe("CANCELLED");
    expect(() => assertExecutedQtyWithinOrder(new Decimal("2"), new Decimal("2.1"))).toThrow(/exceeds order quantity/i);
  });
});
