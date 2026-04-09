#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

FILE="apps/web/components/market/CandlesPanel.tsx"
cp "$FILE" "${FILE}.bak.$(date +%Y%m%d%H%M%S)}"

python3 - <<'PY'
from pathlib import Path
import re
import sys

p = Path("apps/web/components/market/CandlesPanel.tsx")
s = p.read_text()

pattern = re.compile(
    r'''const WINDOW =\s*
(?:.|\n)*?
const from = Math\.max\(0, lastActiveIndex - WINDOW \+ 1\);\s*
const to = Math\.min\(candles\.length - 1, lastActiveIndex \+ 3\);\s*''',
    re.MULTILINE
)

replacement = '''const useExtendedRvaiViewport =
    symbol === "RVAI-USD" && mode === "PAPER";

  const WINDOW = useExtendedRvaiViewport
    ? (
        tf === "1m" ? 1800 :
        tf === "5m" ? 500 :
        tf === "1h" ? 200 :
        200
      )
    : (
        tf === "1m" ? 120 :
        tf === "5m" ? 120 :
        tf === "1h" ? 200 :
        200
      );

  const from = Math.max(0, lastActiveIndex - WINDOW + 1);
  const to = Math.min(candles.length - 1, lastActiveIndex + 3);
'''

new_s, n = pattern.subn(replacement, s, count=1)
if n != 1:
    raise SystemExit("Could not patch WINDOW/from/to block in CandlesPanel.tsx")

p.write_text(new_s)
print("Patched RVAI viewport window in CandlesPanel.tsx")
PY

pnpm --filter web build
docker compose build web --no-cache
docker compose up -d web
