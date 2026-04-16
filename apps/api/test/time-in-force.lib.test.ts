import { describe, expect, it } from "vitest";

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
