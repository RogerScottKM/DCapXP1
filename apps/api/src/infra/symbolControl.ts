// apps/api/src/infra/symbolControl.ts

export type TradingMode = "OPEN" | "HALT" | "CANCEL_ONLY";

export type SymbolControlState = {
  mode: TradingMode;
  reason?: string;
  updatedAt: string; // ISO
  updatedBy?: string;
};

function normalizeSymbol(sym: string) {
  return String(sym ?? "").toUpperCase().trim();
}

class SymbolControlStore {
  private m = new Map<string, SymbolControlState>();

  get(symbol: string): SymbolControlState {
    const s = normalizeSymbol(symbol);
    const cur = this.m.get(s);
    if (cur) return cur;
    return { mode: "OPEN", updatedAt: new Date().toISOString(), updatedBy: "system" };
  }

  set(
    symbol: string,
    next: { mode: TradingMode; reason?: string; updatedBy?: string }
  ): SymbolControlState {
    const s = normalizeSymbol(symbol);
    const state: SymbolControlState = {
      mode: next.mode,
      reason: next.reason,
      updatedBy: next.updatedBy ?? "admin",
      updatedAt: new Date().toISOString(),
    };
    this.m.set(s, state);
    return state;
  }

  clear(symbol: string) {
    const s = normalizeSymbol(symbol);
    this.m.delete(s);
  }

  list() {
    const out: Array<{ symbol: string } & SymbolControlState> = [];
    for (const [symbol, state] of this.m.entries()) out.push({ symbol, ...state });
    return out;
  }
}

export const symbolControl = new SymbolControlStore();

export function isNewOrderAllowed(mode: TradingMode) {
  return mode === "OPEN";
}

export function explainMode(mode: TradingMode) {
  if (mode === "HALT") return "Trading HALTED: no new orders (cancels allowed).";
  if (mode === "CANCEL_ONLY") return "CANCEL_ONLY: no new orders (cancels allowed).";
  return "OPEN";
}
