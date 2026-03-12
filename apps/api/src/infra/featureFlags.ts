// apps/api/src/infra/featureFlags.ts
export type BookLevel = 2 | 3;

export type FeatureFlags = {
  // Defaults used when the client does NOT provide ?level=
  orderbookDefaultLevel: BookLevel;
  streamDefaultLevel: BookLevel;

  // Public access switches
  publicAllowL3: boolean; // if false, only admin can request level=3
  enableSSE: boolean; // if false, only admin can use SSE

  // Metadata
  updatedAt: string;
  updatedBy?: string;
  reason?: string;
};

export type FeatureFlagsPatch =
  Partial<{
    orderbookDefaultLevel: BookLevel;
    streamDefaultLevel: BookLevel;
    publicAllowL3: boolean;
    enableSSE: boolean;
  }> & {
    updatedBy?: string;
    reason?: string;
  };

function envBool(name: string, fallback: boolean) {
  const v = process.env[name];
  if (v === undefined) return fallback;
  return ["1", "true", "yes", "y", "on"].includes(String(v).toLowerCase());
}

function envLevel(name: string, fallback: BookLevel) {
  const v = String(process.env[name] ?? "").trim();
  if (v === "3") return 3;
  if (v === "2") return 2;
  return fallback;
}

function nowIso() {
  return new Date().toISOString();
}

const defaults: FeatureFlags = {
  orderbookDefaultLevel: envLevel("ORDERBOOK_DEFAULT_LEVEL", 2),
  streamDefaultLevel: envLevel("STREAM_DEFAULT_LEVEL", 2),
  publicAllowL3: envBool("PUBLIC_ALLOW_L3", false),
  enableSSE: envBool("ENABLE_SSE", true),
  updatedAt: nowIso(),
  updatedBy: "boot",
  reason: "env defaults",
};

const perSymbol = new Map<string, FeatureFlags>();

function merge(base: FeatureFlags, patch: FeatureFlagsPatch): FeatureFlags {
  return {
    ...base,
    ...patch,
    updatedAt: nowIso(),
    updatedBy: patch.updatedBy ?? base.updatedBy,
    reason: patch.reason ?? base.reason,
  };
}

export const featureFlags = {
  getDefaults(): FeatureFlags {
    return { ...defaults };
  },

  setDefaults(patch: FeatureFlagsPatch): FeatureFlags {
    const next = merge(defaults, patch);
    Object.assign(defaults, next);
    return { ...defaults };
  },

  get(symbol?: string): FeatureFlags {
    if (!symbol) return { ...defaults };
    const key = symbol.toUpperCase();
    const cur = perSymbol.get(key);
    return cur ? { ...cur } : { ...defaults };
  },

  set(symbol: string, patch: FeatureFlagsPatch): FeatureFlags {
    const key = symbol.toUpperCase();
    const base = perSymbol.get(key) ?? { ...defaults };
    const next = merge(base, patch);
    perSymbol.set(key, next);
    return { ...next };
  },

  clear(symbol: string) {
    perSymbol.delete(symbol.toUpperCase());
  },

  listOverrides(): Array<{ symbol: string; flags: FeatureFlags }> {
    return Array.from(perSymbol.entries()).map(([symbol, flags]) => ({
      symbol,
      flags: { ...flags },
    }));
  },
};
