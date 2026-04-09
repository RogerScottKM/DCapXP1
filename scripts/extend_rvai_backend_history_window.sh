#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

FILE="apps/api/src/botFarm.ts"

if [ ! -f "$FILE" ]; then
  echo "Missing $FILE"
  exit 1
fi

cp "$FILE" "${FILE}.bak.$(date +%Y%m%d%H%M%S)"

python3 - <<'PY'
from pathlib import Path
import sys

path = Path("apps/api/src/botFarm.ts")
text = path.read_text()

old_target = 'const targetSpanMs = Number(process.env.RVAI_HISTORY_SPAN_MS ?? 8 * 60 * 60 * 1000);'
new_target = 'const targetSpanMs = Number(process.env.RVAI_HISTORY_SPAN_MS ?? 36 * 60 * 60 * 1000);'

old_step = 'const stepMs = Number(process.env.RVAI_HISTORY_STEP_MS ?? 30_000);'
new_step = 'const stepMs = Number(process.env.RVAI_HISTORY_STEP_MS ?? 30_000);'

old_points = 'const maxPoints = Number(process.env.RVAI_HISTORY_MAX_POINTS ?? 960);'
new_points = 'const maxPoints = Number(process.env.RVAI_HISTORY_MAX_POINTS ?? 5000);'

missing = []
for old in [old_target, old_step, old_points]:
    if old not in text:
        missing.append(old)

if missing:
    print("Could not find expected RVAI history config lines.")
    for m in missing:
        print("---")
        print(m)
    sys.exit(1)

text = text.replace(old_target, new_target, 1)
text = text.replace(old_step, new_step, 1)
text = text.replace(old_points, new_points, 1)

path.write_text(text)
print("Patched botFarm.ts")
PY

echo
echo "==> Verify patch"
rg -n 'RVAI_HISTORY_SPAN_MS|RVAI_HISTORY_STEP_MS|RVAI_HISTORY_MAX_POINTS' "$FILE" || true

echo
echo "==> Build check"
pnpm --filter api build

echo
echo "✅ RVAI backend history window extended."
echo
echo "Next:"
echo "  docker compose build api --no-cache"
echo "  docker compose up -d api"
echo
echo "Then check:"
echo "  docker compose logs api --tail=120"
