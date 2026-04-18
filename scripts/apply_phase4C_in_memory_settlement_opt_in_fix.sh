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
import re
import sys

root = Path(sys.argv[1])

pkg_path = root / "apps/api/package.json"
trade_path = root / "apps/api/src/routes/trade.ts"
orders_path = root / "apps/api/src/routes/orders.ts"
submit_path = root / "apps/api/src/lib/matching/submit-limit-order.ts"

for p in [pkg_path, trade_path, orders_path, submit_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:matching:in-memory-settlement"] = "vitest run test/in-memory-settlement-integration.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

# Ensure submit service still supports preferredEngine
submit_text = submit_path.read_text()
if "preferredEngine?: string | null;" not in submit_text:
    submit_text = submit_text.replace(
        '  source: "HUMAN" | "AGENT";\n};',
        '  source: "HUMAN" | "AGENT";\n  preferredEngine?: string | null;\n};',
        1,
    )
if 'selectMatchingEngine(input.preferredEngine as any)' not in submit_text:
    submit_text = submit_text.replace(
        "const selectedEngine = engine ?? selectMatchingEngine();",
        "const selectedEngine = engine ?? selectMatchingEngine(input.preferredEngine as any);",
        1,
    )
submit_path.write_text(submit_text)

# Orders route: keep or add preferredEngine gate if missing
orders_text = orders_path.read_text()
if 'ALLOW_IN_MEMORY_MATCHING === "true"' not in orders_text:
    m = re.search(r'(\s*const payload = .*?parse\(req\.body\);\n)', orders_text)
    if m:
        insert = (
            m.group(1)
            + '      const preferredEngine = process.env.ALLOW_IN_MEMORY_MATCHING === "true"\n'
            + '        ? (req.get("x-matching-engine") ?? undefined)\n'
            + '        : undefined;\n'
        )
        orders_text = orders_text.replace(m.group(1), insert, 1)
if 'preferredEngine,' not in orders_text and 'source: "HUMAN"' in orders_text:
    orders_text = orders_text.replace(
        '          source: "HUMAN",\n',
        '          source: "HUMAN",\n          preferredEngine,\n',
        1,
    )
orders_path.write_text(orders_text)

# Trade route: add preferredEngine gate robustly
trade_text = trade_path.read_text()

if 'ALLOW_IN_MEMORY_MATCHING === "true"' not in trade_text:
    m = re.search(r'(\s*const payload = .*?parse\(req\.body\);\n)', trade_text)
    if not m:
        raise SystemExit("Could not find payload parse anchor in trade.ts")
    insert = (
        m.group(1)
        + '      const preferredEngine = process.env.ALLOW_IN_MEMORY_MATCHING === "true"\n'
        + '        ? (req.get("x-matching-engine") ?? undefined)\n'
        + '        : undefined;\n'
    )
    trade_text = trade_text.replace(m.group(1), insert, 1)

if 'preferredEngine,' not in trade_text and 'source: "AGENT"' in trade_text:
    trade_text = trade_text.replace(
        '          source: "AGENT",\n',
        '          source: "AGENT",\n          preferredEngine,\n',
        1,
    )

trade_path.write_text(trade_text)

print("Patched trade.ts preferred-engine opt-in gate for Phase 4C and confirmed preferredEngine support in submit-limit-order.ts.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 4C fix patch applied."
