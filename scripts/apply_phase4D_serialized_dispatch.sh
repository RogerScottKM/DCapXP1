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

for p in [pkg_path, submit_path, index_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:matching:serialized-dispatch"] = "vitest run test/matching-serialized-dispatch.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

matching_dir = root / "apps/api/src/lib/matching"
dispatcher_path = matching_dir / "serialized-dispatch.ts"
test_path = root / "apps/api/test/matching-serialized-dispatch.test.ts"

dispatcher_path.write_text(dedent("""\
type TaskFactory<T> = () => Promise<T>;

const lanes = new Map<string, Promise<unknown>>();

export async function runSerializedByKey<T>(
  key: string,
  taskFactory: TaskFactory<T>,
): Promise<T> {
  const previous = lanes.get(key) ?? Promise.resolve();

  let release!: () => void;
  const current = new Promise<void>((resolve) => {
    release = resolve;
  });

  lanes.set(
    key,
    previous
      .catch(() => undefined)
      .then(() => current),
  );

  try {
    await previous.catch(() => undefined);
    return await taskFactory();
  } finally {
    release();
    const lane = lanes.get(key);
    if (lane === current || lane === previous) {
      lanes.delete(key);
    } else {
      queueMicrotask(() => {
        if (lanes.get(key) === current) {
          lanes.delete(key);
        }
      });
    }
  }
}

export function buildSymbolModeKey(symbol: string, mode: string): string {
  return `${symbol}:${mode}`;
}

export function getSerializedLaneCount(): number {
  return lanes.size;
}

export function resetSerializedDispatchForTests(): void {
  lanes.clear();
}
"""))

submit_text = submit_path.read_text()
if 'import { buildSymbolModeKey, runSerializedByKey } from "./serialized-dispatch";' not in submit_text:
    submit_text = submit_text.replace(
        'import { selectMatchingEngine } from "./select-engine";\n',
        'import { selectMatchingEngine } from "./select-engine";\nimport { buildSymbolModeKey, runSerializedByKey } from "./serialized-dispatch";\n',
        1,
    )

old_block = dedent("""\
    const engineResult = await selectedEngine.executeLimitOrder(
      {
        orderId: order.id,
        quoteFeeBps: input.quoteFeeBps ?? "0",
      },
      tx,
    );
""")

new_block = dedent("""\
    const executeThroughSelectedEngine = () =>
      selectedEngine.executeLimitOrder(
        {
          orderId: order.id,
          quoteFeeBps: input.quoteFeeBps ?? "0",
        },
        tx,
      );

    const engineResult =
      selectedEngine.name === "IN_MEMORY_MATCHER"
        ? await runSerializedByKey(
            buildSymbolModeKey(input.symbol, String(input.mode)),
            executeThroughSelectedEngine,
          )
        : await executeThroughSelectedEngine();
""")

if old_block in submit_text:
    submit_text = submit_text.replace(old_block, new_block, 1)
elif 'runSerializedByKey(' not in submit_text:
    raise SystemExit("Could not patch submit-limit-order.ts engine dispatch block")

submit_path.write_text(submit_text)

index_text = index_path.read_text()
export_line = 'export * from "./serialized-dispatch";'
if export_line not in index_text:
    index_text = index_text.rstrip() + "\n" + export_line + "\n"
index_path.write_text(index_text)

test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(dedent("""\
import { beforeEach, describe, expect, it, vi } from "vitest";

const { reserveOrderOnPlacement, selectMatchingEngine } = vi.hoisted(() => ({
  reserveOrderOnPlacement: vi.fn(),
  selectMatchingEngine: vi.fn(),
}));

vi.mock("../src/lib/ledger", () => ({
  reserveOrderOnPlacement,
}));
vi.mock("../src/lib/matching/select-engine", () => ({
  selectMatchingEngine,
}));

import {
  buildSymbolModeKey,
  getSerializedLaneCount,
  resetSerializedDispatchForTests,
  runSerializedByKey,
} from "../src/lib/matching/serialized-dispatch";
import { submitLimitOrder } from "../src/lib/matching/submit-limit-order";

describe("matching serialized dispatch", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    resetSerializedDispatchForTests();
  });

  it("serializes tasks for the same symbol:mode key", async () => {
    const events: string[] = [];

    const first = runSerializedByKey("BTC-USD:PAPER", async () => {
      events.push("first:start");
      await new Promise((resolve) => setTimeout(resolve, 20));
      events.push("first:end");
      return "first";
    });

    const second = runSerializedByKey("BTC-USD:PAPER", async () => {
      events.push("second:start");
      events.push("second:end");
      return "second";
    });

    const result = await Promise.all([first, second]);

    expect(result).toEqual(["first", "second"]);
    expect(events).toEqual(["first:start", "first:end", "second:start", "second:end"]);
  });

  it("allows different symbol:mode keys to progress independently", async () => {
    const events: string[] = [];

    const first = runSerializedByKey("BTC-USD:PAPER", async () => {
      events.push("btc:start");
      await new Promise((resolve) => setTimeout(resolve, 20));
      events.push("btc:end");
      return "btc";
    });

    const second = runSerializedByKey("ETH-USD:PAPER", async () => {
      events.push("eth:start");
      events.push("eth:end");
      return "eth";
    });

    const result = await Promise.all([first, second]);

    expect(result.sort()).toEqual(["btc", "eth"]);
    expect(events[0]).toBe("btc:start");
    expect(events).toContain("eth:start");
    expect(events).toContain("eth:end");
  });

  it("submitLimitOrder serializes only the in-memory engine path by symbol:mode", async () => {
    reserveOrderOnPlacement.mockResolvedValue({ id: "reserve-1" });

    const tx = {
      order: {
        create: vi
          .fn()
          .mockResolvedValueOnce({
            id: 101n,
            symbol: "BTC-USD",
            side: "BUY",
            price: "100",
            qty: "1",
            status: "OPEN",
            timeInForce: "GTC",
            mode: "PAPER",
            userId: "user-1",
          })
          .mockResolvedValueOnce({
            id: 102n,
            symbol: "BTC-USD",
            side: "BUY",
            price: "100",
            qty: "1",
            status: "OPEN",
            timeInForce: "GTC",
            mode: "PAPER",
            userId: "user-2",
          }),
      },
    };

    const fakeDb = {
      $transaction: vi.fn(async (fn: any) => fn(tx)),
    };

    const events: string[] = [];
    const engine = {
      name: "IN_MEMORY_MATCHER",
      executeLimitOrder: vi
        .fn()
        .mockImplementationOnce(async () => {
          events.push("first:start");
          await new Promise((resolve) => setTimeout(resolve, 20));
          events.push("first:end");
          return {
            execution: { fills: [], remainingQty: "1", tifAction: "KEEP_OPEN", restingOrderId: "101" },
            orderReconciliation: { ok: true },
            engine: "IN_MEMORY_MATCHER",
          };
        })
        .mockImplementationOnce(async () => {
          events.push("second:start");
          events.push("second:end");
          return {
            execution: { fills: [], remainingQty: "1", tifAction: "KEEP_OPEN", restingOrderId: "102" },
            orderReconciliation: { ok: true },
            engine: "IN_MEMORY_MATCHER",
          };
        }),
    };

    selectMatchingEngine.mockReturnValue(engine);

    const first = submitLimitOrder(
      {
        userId: "user-1",
        symbol: "BTC-USD",
        side: "BUY",
        price: "100",
        qty: "1",
        mode: "PAPER" as any,
        source: "HUMAN",
        preferredEngine: "IN_MEMORY_MATCHER",
      },
      fakeDb as any,
    );

    const second = submitLimitOrder(
      {
        userId: "user-2",
        symbol: "BTC-USD",
        side: "BUY",
        price: "100",
        qty: "1",
        mode: "PAPER" as any,
        source: "HUMAN",
        preferredEngine: "IN_MEMORY_MATCHER",
      },
      fakeDb as any,
    );

    await Promise.all([first, second]);

    expect(selectMatchingEngine).toHaveBeenCalledTimes(2);
    expect(events).toEqual(["first:start", "first:end", "second:start", "second:end"]);
    expect(getSerializedLaneCount()).toBe(0);
  });

  it("buildSymbolModeKey uses symbol and mode deterministically", () => {
    expect(buildSymbolModeKey("BTC-USD", "PAPER")).toBe("BTC-USD:PAPER");
  });
});
"""))

print("Patched package.json, added serialized per-symbol dispatch for in-memory engine execution in submit-limit-order.ts, and wrote apps/api/test/matching-serialized-dispatch.test.ts for Phase 4D.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 4D patch applied."
