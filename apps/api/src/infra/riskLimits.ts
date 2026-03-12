// apps/api/src/infra/riskLimits.ts
import { Decimal } from "@prisma/client/runtime/library";

export type RiskLimits = {
  // Per-new-order limits
  maxOrderQty?: string;       // Decimal string
  maxOrderNotional?: string;  // Decimal string (price * qty)

  // Exposure limits (per-user per-symbol)
  maxOpenOrders?: number;     // integer
};

export type RiskLimitsState = RiskLimits & {
  updatedAt: string; // ISO
  updatedBy?: string;
  reason?: string;
};

function normalizeSymbol(sym: string) {
  return String(sym ?? "").toUpperCase().trim();
}

function toDecimalString(v: unknown): string | undefined {
  if (v === undefined || v === null) return undefined;
  const s = String(v).trim();
  if (!s) return undefined;

  // Validate it parses as Decimal and is >= 0
  const d = new Decimal(s);
  if (d.isNaN() || d.isNeg()) return undefined;
  return d.toString();
}

class RiskLimitsStore {
  private defaults: RiskLimitsState = {
    // sensible demo defaults (tune anytime)
    maxOrderQty: "1000000",
    maxOrderNotional: "1000000000",
    maxOpenOrders: 1000,
    updatedAt: new Date().toISOString(),
    updatedBy: "system",
    reason: "defaults",
  };

  private overrides = new Map<string, RiskLimitsState>(); // per symbol

  get(symbol: string): RiskLimitsState {
    const s = normalizeSymbol(symbol);
    const ov = this.overrides.get(s);
    if (!ov) return { ...this.defaults };
    return {
      ...this.defaults,
      ...ov,
    };
  }

  getDefaults(): RiskLimitsState {
    return { ...this.defaults };
  }

  listOverrides() {
    const out: Array<{ symbol: string } & RiskLimitsState> = [];
    for (const [symbol, state] of this.overrides.entries()) out.push({ symbol, ...state });
    return out;
  }

  setDefaults(next: Partial<RiskLimits> & { reason?: string; updatedBy?: string }) {
    const updated: RiskLimitsState = {
      ...this.defaults,
      maxOrderQty: next.maxOrderQty !== undefined ? toDecimalString(next.maxOrderQty) : this.defaults.maxOrderQty,
      maxOrderNotional:
        next.maxOrderNotional !== undefined ? toDecimalString(next.maxOrderNotional) : this.defaults.maxOrderNotional,
      maxOpenOrders: next.maxOpenOrders !== undefined ? next.maxOpenOrders : this.defaults.maxOpenOrders,
      reason: next.reason ?? this.defaults.reason,
      updatedBy: next.updatedBy ?? "admin",
      updatedAt: new Date().toISOString(),
    };

    this.defaults = updated;
    return { ...this.defaults };
  }

  set(symbol: string, next: Partial<RiskLimits> & { reason?: string; updatedBy?: string }) {
    const s = normalizeSymbol(symbol);

    const prev = this.overrides.get(s);
    const base = prev ?? { ...this.defaults };

    const updated: RiskLimitsState = {
      ...base,
      maxOrderQty: next.maxOrderQty !== undefined ? toDecimalString(next.maxOrderQty) : base.maxOrderQty,
      maxOrderNotional:
        next.maxOrderNotional !== undefined ? toDecimalString(next.maxOrderNotional) : base.maxOrderNotional,
      maxOpenOrders: next.maxOpenOrders !== undefined ? next.maxOpenOrders : base.maxOpenOrders,
      reason: next.reason ?? base.reason,
      updatedBy: next.updatedBy ?? "admin",
      updatedAt: new Date().toISOString(),
    };

    this.overrides.set(s, updated);
    return { ...updated };
  }

  clear(symbol: string) {
    const s = normalizeSymbol(symbol);
    this.overrides.delete(s);
  }
}

export const riskLimits = new RiskLimitsStore();
