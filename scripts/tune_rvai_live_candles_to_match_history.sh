#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

FILE="apps/api/src/botFarm.ts"
BACKUP="${FILE}.bak.$(date +%Y%m%d%H%M%S)"

cp "$FILE" "$BACKUP"
echo "Backup created: $BACKUP"

python3 - <<'PY'
from pathlib import Path
import re
import sys

p = Path("apps/api/src/botFarm.ts")
s = p.read_text()

original = s

def must_replace_exact(old: str, new: str, label: str):
    global s
    if old not in s:
        raise SystemExit(f"[FAIL] Could not find exact pattern for {label}")
    s = s.replace(old, new, 1)
    print(f"[OK] {label}")

def must_replace_regex(pattern: str, repl: str, label: str):
    global s
    new_s, n = re.subn(pattern, repl, s, count=1, flags=re.MULTILINE)
    if n != 1:
        raise SystemExit(f"[FAIL] Could not regex-patch {label}")
    s = new_s
    print(f"[OK] {label}")

# 1) Reduce RVAI base drift in config
must_replace_regex(
    r'("RVAI-USD":\s*\{(?:.|\n)*?driftPct:\s*)0\.00100(\s*,)',
    r'\g<1>0.00028\2',
    "RVAI config driftPct 0.00100 -> 0.00028"
)

# 2) Make live RVAI trade prints snap back closer to mid
# before:
# pxNum = mid + (pxNum - mid) * 0.68;
# after:
# pxNum = isRvai ? mid + (pxNum - mid) * 0.42 : mid + (pxNum - mid) * 0.68;
must_replace_exact(
    '  pxNum = mid + (pxNum - mid) * 0.68;',
    '  pxNum = isRvai ? mid + (pxNum - mid) * 0.42 : mid + (pxNum - mid) * 0.68;',
    "RVAI print pullback tightening"
)

# 3) Strengthen RVAI soft-centering in live synthesizer
must_replace_exact(
    '          mid = mid + (rvaiSoftCenter - mid) * 0.028;',
    '          mid = mid + (rvaiSoftCenter - mid) * 0.075;',
    "RVAI soft-center strength 0.028 -> 0.075"
)

# 4) Slightly tame RVAI step-to-step move cap if the exact line exists
# This is optional but helpful. We only patch if found.
optional_old = '          mid = clamp(mid, prevMid - maxStepAbs, prevMid + maxStepAbs);'
optional_new = '''          const rvaiStepTightener = symbol === "RVAI-USD" ? 0.58 : 1;
          mid = clamp(mid, prevMid - maxStepAbs * rvaiStepTightener, prevMid + maxStepAbs * rvaiStepTightener);'''
if optional_old in s:
    s = s.replace(optional_old, optional_new, 1)
    print("[OK] RVAI step clamp tightened")
else:
    print("[WARN] RVAI step clamp line not patched (exact line not found)")

if s == original:
    raise SystemExit("[FAIL] No changes were made")

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
