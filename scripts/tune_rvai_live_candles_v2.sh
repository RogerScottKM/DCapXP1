#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

FILE="apps/api/src/botFarm.ts"
BACKUP="${FILE}.bak.$(date +%Y%m%d%H%M%S)}"

cp "$FILE" "$BACKUP"
echo "Backup created: $BACKUP"

python3 - <<'PY'
from pathlib import Path
import re
import sys

p = Path("apps/api/src/botFarm.ts")
s = p.read_text()
orig = s

def sub_once(pattern, repl, label):
    global s
    new_s, n = re.subn(pattern, repl, s, count=1, flags=re.MULTILINE)
    if n != 1:
        print(f"[WARN] {label} not patched")
    else:
        s = new_s
        print(f"[OK] {label}")

# 1) RVAI config driftPct -> lower again
sub_once(
    r'("RVAI-USD":\s*\{(?:.|\n)*?driftPct:\s*)0\.\d+(\s*,)',
    r'\g<1>0.00012\2',
    "RVAI driftPct -> 0.00012"
)

# 2) Stronger RVAI print pullback to mid
# handles either previous patched state or original
sub_once(
    r'pxNum = isRvai \? mid \+ \(pxNum - mid\) \* 0\.\d+ : mid \+ \(pxNum - mid\) \* 0\.68;',
    'pxNum = isRvai ? mid + (pxNum - mid) * 0.24 : mid + (pxNum - mid) * 0.68;',
    "RVAI print pullback -> 0.24"
)
sub_once(
    r'pxNum = mid \+ \(pxNum - mid\) \* 0\.68;',
    'pxNum = isRvai ? mid + (pxNum - mid) * 0.24 : mid + (pxNum - mid) * 0.68;',
    "RVAI print pullback from original form -> 0.24"
)

# 3) Stronger RVAI soft-center pull
sub_once(
    r'mid = mid \+ \(rvaiSoftCenter - mid\) \* 0\.\d+;',
    'mid = mid + (rvaiSoftCenter - mid) * 0.14;',
    "RVAI soft-center -> 0.14"
)

# 4) Tighter RVAI step clamp if previous helper exists
sub_once(
    r'const rvaiStepTightener = symbol === "RVAI-USD" \? 0\.\d+ : 1;',
    'const rvaiStepTightener = symbol === "RVAI-USD" ? 0.22 : 1;',
    "RVAI step tightener -> 0.22"
)

# 5) If no rvaiStepTightener helper exists yet, patch the clamp directly
sub_once(
    r'mid = clamp\(mid, prevMid - maxStepAbs, prevMid \+ maxStepAbs\);',
    '''const rvaiStepTightener = symbol === "RVAI-USD" ? 0.22 : 1;
          mid = clamp(mid, prevMid - maxStepAbs * rvaiStepTightener, prevMid + maxStepAbs * rvaiStepTightener);''',
    "Direct step clamp patch -> RVAI 0.22"
)

# 6) Reduce live RVAI wick amplitude at print generation
# line near:
# ? live!.mid + randn() * tick * wick
# : mid + randn() * tick * wick;
sub_once(
    r'\?\s*live!\.mid \+ randn\(\) \* tick \* wick\s*:\s*mid \+ randn\(\) \* tick \* wick;',
    '''? live!.mid + randn() * tick * (isRvai ? wick * 0.45 : wick)
    : mid + randn() * tick * (isRvai ? wick * 0.45 : wick);''',
    "RVAI wick tamer -> 0.45x"
)

if s == orig:
    raise SystemExit("[FAIL] No changes made to botFarm.ts")

p.write_text(s)
print("Patched apps/api/src/botFarm.ts")
PY

echo
echo "==> Build check"
pnpm --filter api build

echo
echo "==> Rebuild + restart API"
docker compose build api --no-cache
docker compose up -d api

echo
echo "==> Recent API logs"
docker compose logs api --tail=120
