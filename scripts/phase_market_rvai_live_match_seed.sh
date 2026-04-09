#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

FILE="apps/api/src/botFarm.ts"

if [ ! -f "$FILE" ]; then
  echo "Missing $FILE"
  exit 1
fi

cp "$FILE" "${FILE}.bak.$(date +%Y%m%d%H%M%S)}"

python3 - <<'PY'
from pathlib import Path
import re
import sys

path = Path("apps/api/src/botFarm.ts")
text = path.read_text()

replacements = [
    # RVAI base band profile
    ('driftPct: 0.00135,', 'driftPct: 0.00095,'),
    ('wickTicks: 6,', 'wickTicks: 4,'),
    ('pullToAnchor: 0.065,', 'pullToAnchor: 0.095,'),
    ('anchorNoisePct: 0.0035,', 'anchorNoisePct: 0.0018,'),
    ('jumpProb: 0.006,', 'jumpProb: 0.0030,'),
    ('jumpTicksMin: 6,', 'jumpTicksMin: 3,'),
    ('jumpTicksMax: 22,', 'jumpTicksMax: 10,'),
    ('forceTradeEveryMs: 2400,', 'forceTradeEveryMs: 2800,'),

    # RVAI live sweep / anchor motion
    ('const sweepBias = (0.5 - bandPos) * range * 0.035;', 'const sweepBias = (0.5 - bandPos) * range * 0.010;'),

    # RVAI loop step cap
    ('const maxStepAbs = 0.0022;', 'const maxStepAbs = 0.0009;'),

    # RVAI soft-center pull
    ('mid = mid + (rvaiSoftCenter - mid) * 0.015;', 'mid = mid + (rvaiSoftCenter - mid) * 0.040;'),

    # RVAI wick profile inside emitPaperTrade
    ('? cfg.wickTicks *\n      (regime === "calm" ? 0.16 : regime === "active" ? 0.24 : 0.34)',
     '? cfg.wickTicks *\n      (regime === "calm" ? 0.10 : regime === "active" ? 0.16 : 0.22)'),

    # RVAI rare wick-outs
    ('? regime === "panic"\n    ? 0.018\n    : regime === "active"\n    ? 0.010\n    : 0.004',
     '? regime === "panic"\n    ? 0.010\n    : regime === "active"\n    ? 0.006\n    : 0.0025'),

    # RVAI wick-out size
    ('pxNum += randn() * tick * wick * (isRvai ? 0.55 : 2.2);',
     'pxNum += randn() * tick * wick * (isRvai ? 0.35 : 2.2);'),

    # RVAI per-trade hard cap
    ('const maxTradeDeviation = 0.0028;', 'const maxTradeDeviation = 0.0011;'),

    # Make trade feedback into mid slightly gentler
    ('s.mid = clamp(s.mid * 0.75 + pxNum * 0.25, lo, hi);',
     's.mid = clamp(s.mid * 0.82 + pxNum * 0.18, lo, hi);'),
]

missing = []
for old, new in replacements:
    if old in text:
        text = text.replace(old, new)
    else:
        missing.append(old)

if missing:
    print("Some expected botFarm snippets were not found exactly.")
    print("Missing:")
    for m in missing:
        print("---")
        print(m)
    sys.exit(1)

path.write_text(text)
print("Patched botFarm.ts")
PY

echo
echo "==> Quick verify"
rg -n 'driftPct: 0.00095|wickTicks: 4|pullToAnchor: 0.095|anchorNoisePct: 0.0018|jumpProb: 0.0030|jumpTicksMin: 3|jumpTicksMax: 10|forceTradeEveryMs: 2800|maxStepAbs = 0.0009|rvaiSoftCenter|maxTradeDeviation = 0.0011|0.010;|0.006|0.0025|0.35|0.82 \+ pxNum \* 0.18' apps/api/src/botFarm.ts || true

echo
echo "==> Build check"
pnpm --filter api build

echo
echo "Next:"
echo "  docker compose build api --no-cache"
echo "  docker compose up -d api"
echo
echo "Optional:"
echo '  docker compose logs api --tail=120'
