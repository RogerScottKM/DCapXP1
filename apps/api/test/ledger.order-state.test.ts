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
