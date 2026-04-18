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
import sys
from textwrap import dedent

root = Path(sys.argv[1])

pkg_path = root / "apps/api/package.json"
submit_path = root / "apps/api/src/lib/matching/submit-limit-order.ts"
index_path = root / "apps/api/src/lib/matching/index.ts"
helper_path = root / "apps/api/src/lib/matching/admission-controls.ts"
test_path = root / "apps/api/test/admission-controls.test.ts"

for p in [pkg_path, submit_path, index_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:matching:admission-controls"] = "vitest run test/admission-controls.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

helper_path.parent.mkdir(parents=True, exist_ok=True)
helper_path.write_text(dedent("""\
import { Decimal } from "@prisma/client/runtime/library";

export class AdmissionControlError extends Error {
  readonly status = 429;
  readonly code = "ADMISSION_CONTROL_REJECTED";

  constructor(message: string) {
    super(message);
    this.name = "AdmissionControlError";
  }
}

type WindowState = {
  timestamps: number[];
};

const orderWindowState = new Map<string, WindowState>();

function parseCsvList(value?: string | null): string[] {
  return String(value ?? "")
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
}

function getEnvNumber(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function resetAdmissionControlCountersForTests(): void {
  orderWindowState.clear();
}

export function computePriceDeviationBps(
  referencePrice: string | number | Decimal,
  submittedPrice: string | number | Decimal,
): Decimal {
  const reference = new Decimal(referencePrice);
  const submitted = new Decimal(submittedPrice);

  if (reference.lte(0)) return new Decimal(0);

  return submitted
    .minus(reference)
    .abs()
    .div(reference)
    .mul(10000);
}

export function assertWithinPriceBand(input: {
  referencePrice: string | number | Decimal;
  submittedPrice: string | number | Decimal;
  maxDeviationBps: number;
  symbol: string;
}): void {
  if (input.maxDeviationBps <= 0) return;

  const deviation = computePriceDeviationBps(input.referencePrice, input.submittedPrice);
  if (deviation.gt(input.maxDeviationBps)) {
    throw new AdmissionControlError(
      `Price band exceeded for ${input.symbol}: ${deviation.toFixed(2)}bps > ${input.maxDeviationBps}bps`,
    );
  }
}

export function assertSymbolEnabled(input: {
  symbol: string;
  marketEnabled?: boolean | null;
  disabledSymbols?: string[];
}): void {
  const disabled = new Set((input.disabledSymbols ?? []).map((value) => value.trim()).filter(Boolean));
  if (input.marketEnabled === false || disabled.has(input.symbol)) {
    throw new AdmissionControlError(`Trading disabled for ${input.symbol}`);
  }
}

export function consumeSlidingWindowLimit(input: {
  key: string;
  limit: number;
  windowMs?: number;
  nowMs?: number;
}): { used: number; remaining: number } {
  const windowMs = input.windowMs ?? 60_000;
  const nowMs = input.nowMs ?? Date.now();

  if (input.limit <= 0) {
    return { used: 0, remaining: Number.MAX_SAFE_INTEGER };
  }

  const existing = orderWindowState.get(input.key) ?? { timestamps: [] };
  existing.timestamps = existing.timestamps.filter((ts) => ts > nowMs - windowMs);

  if (existing.timestamps.length >= input.limit) {
    throw new AdmissionControlError(
      `Rate limit exceeded for ${input.key}: ${existing.timestamps.length}/${input.limit} in ${windowMs}ms`,
    );
  }

  existing.timestamps.push(nowMs);
  orderWindowState.set(input.key, existing);

  return {
    used: existing.timestamps.length,
    remaining: Math.max(0, input.limit - existing.timestamps.length),
  };
}

export async function enforceAdmissionControls(input: {
  db: any;
  userId: string;
  symbol: string;
  mode: string;
  price: string;
}): Promise<void> {
  const disabledSymbols = parseCsvList(process.env.MATCH_DISABLED_SYMBOLS);
  const maxDeviationBps = getEnvNumber("MATCH_MAX_PRICE_DEVIATION_BPS", 1500);
  const userOrderLimit = getEnvNumber("MATCH_MAX_ORDERS_PER_MINUTE_PER_USER", 60);
  const symbolOrderLimit = getEnvNumber("MATCH_MAX_ORDERS_PER_MINUTE_PER_SYMBOL", 600);

  let marketRecord: any = null;
  const marketRepo = input.db?.market;
  if (marketRepo?.findUnique) {
    marketRecord = await marketRepo.findUnique({ where: { symbol: input.symbol } });
  } else if (marketRepo?.findFirst) {
    marketRecord = await marketRepo.findFirst({ where: { symbol: input.symbol } });
  }

  assertSymbolEnabled({
    symbol: input.symbol,
    marketEnabled: marketRecord?.enabled,
    disabledSymbols,
  });

  const tradeRepo = input.db?.trade;
  const latestTrade =
    tradeRepo?.findFirst
      ? await tradeRepo.findFirst({
          where: {
            symbol: input.symbol,
            mode: input.mode,
          },
          orderBy: { id: "desc" },
        })
      : null;

  if (latestTrade?.price != null) {
    assertWithinPriceBand({
      referencePrice: latestTrade.price,
      submittedPrice: input.price,
      maxDeviationBps,
      symbol: input.symbol,
    });
  }

  consumeSlidingWindowLimit({
    key: `user:${input.userId}:${input.symbol}:${input.mode}`,
    limit: userOrderLimit,
  });

  consumeSlidingWindowLimit({
    key: `symbol:${input.symbol}:${input.mode}`,
    limit: symbolOrderLimit,
  });
}
"""))

submit_text = submit_path.read_text()
import_line = 'import { enforceAdmissionControls } from "./admission-controls";'
if import_line not in submit_text:
    anchor = 'import { buildMatchingEventsFromSubmission, emitMatchingEvents } from "./matching-events";'
    if anchor not in submit_text:
        raise SystemExit("Could not find matching-events import anchor in submit-limit-order.ts")
    submit_text = submit_text.replace(anchor, anchor + '\n' + import_line, 1)

call_block = dedent("""\
    await enforceAdmissionControls({
      db: tx as any,
      userId: input.userId,
      symbol: input.symbol,
      mode: String(input.mode),
      price: input.price,
    });

""")
if 'await enforceAdmissionControls({' not in submit_text:
    anchor = '    const order = await tx.order.create({'
    if anchor not in submit_text:
        raise SystemExit("Could not find tx.order.create anchor in submit-limit-order.ts")
    submit_text = submit_text.replace(anchor, call_block + anchor, 1)

submit_path.write_text(submit_text)

index_text = index_path.read_text()
export_line = 'export * from "./admission-controls";'
if export_line not in index_text:
    index_text = index_text.rstrip() + "\n" + export_line + "\n"
index_path.write_text(index_text)

test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(dedent("""\
import { beforeEach, describe, expect, it } from "vitest";

import {
  assertSymbolEnabled,
  assertWithinPriceBand,
  consumeSlidingWindowLimit,
  enforceAdmissionControls,
  resetAdmissionControlCountersForTests,
} from "../src/lib/matching/admission-controls";

describe("admission controls", () => {
  beforeEach(() => {
    delete process.env.MATCH_DISABLED_SYMBOLS;
    delete process.env.MATCH_MAX_PRICE_DEVIATION_BPS;
    delete process.env.MATCH_MAX_ORDERS_PER_MINUTE_PER_USER;
    delete process.env.MATCH_MAX_ORDERS_PER_MINUTE_PER_SYMBOL;
    resetAdmissionControlCountersForTests();
  });

  it("rejects disabled symbols from either market.enabled or env kill switch", () => {
    expect(() =>
      assertSymbolEnabled({
        symbol: "BTC-USD",
        marketEnabled: false,
        disabledSymbols: [],
      }),
    ).toThrow(/Trading disabled/);

    expect(() =>
      assertSymbolEnabled({
        symbol: "ETH-USD",
        marketEnabled: true,
        disabledSymbols: ["ETH-USD"],
      }),
    ).toThrow(/Trading disabled/);
  });

  it("rejects prices outside the configured max deviation band", () => {
    expect(() =>
      assertWithinPriceBand({
        referencePrice: "100",
        submittedPrice: "110",
        maxDeviationBps: 500,
        symbol: "BTC-USD",
      }),
    ).toThrow(/Price band exceeded/);

    expect(() =>
      assertWithinPriceBand({
        referencePrice: "100",
        submittedPrice: "103",
        maxDeviationBps: 500,
        symbol: "BTC-USD",
      }),
    ).not.toThrow();
  });

  it("enforces per-user and per-symbol sliding-window rate limits", () => {
    consumeSlidingWindowLimit({
      key: "user:u1:BTC-USD:PAPER",
      limit: 2,
      nowMs: 1000,
      windowMs: 60000,
    });
    consumeSlidingWindowLimit({
      key: "user:u1:BTC-USD:PAPER",
      limit: 2,
      nowMs: 1001,
      windowMs: 60000,
    });

    expect(() =>
      consumeSlidingWindowLimit({
        key: "user:u1:BTC-USD:PAPER",
        limit: 2,
        nowMs: 1002,
        windowMs: 60000,
      }),
    ).toThrow(/Rate limit exceeded/);
  });

  it("enforceAdmissionControls consults latest trade, kill switch, and both rate windows", async () => {
    process.env.MATCH_MAX_PRICE_DEVIATION_BPS = "500";
    process.env.MATCH_MAX_ORDERS_PER_MINUTE_PER_USER = "2";
    process.env.MATCH_MAX_ORDERS_PER_MINUTE_PER_SYMBOL = "3";

    const db = {
      market: {
        findUnique: async ({ where }: any) => ({ symbol: where.symbol, enabled: true }),
      },
      trade: {
        findFirst: async () => ({ id: 55n, price: "100" }),
      },
    };

    await enforceAdmissionControls({
      db,
      userId: "user-1",
      symbol: "BTC-USD",
      mode: "PAPER",
      price: "103",
    });

    await enforceAdmissionControls({
      db,
      userId: "user-1",
      symbol: "BTC-USD",
      mode: "PAPER",
      price: "104",
    });

    await expect(
      enforceAdmissionControls({
        db,
        userId: "user-1",
        symbol: "BTC-USD",
        mode: "PAPER",
        price: "104",
      }),
    ).rejects.toThrow(/Rate limit exceeded/);
  });
});
"""))

print("Patched package.json, added admission-controls.ts, wired submit-limit-order.ts through circuit-breaker admission checks, and wrote apps/api/test/admission-controls.test.ts for Phase 5B.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 5B patch applied."
