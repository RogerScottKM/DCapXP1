#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

CANDLES="apps/web/components/market/CandlesPanel.tsx"
OPEN="apps/web/components/market/OpenOrdersPanel.tsx"
POS="apps/web/components/market/PositionsPanel.tsx"

for f in "$CANDLES" "$OPEN" "$POS"; do
  if [ ! -f "$f" ]; then
    echo "Missing $f"
    exit 1
  fi
  backup "$f"
done

python3 - <<'PY'
from pathlib import Path
import re

candles = Path("apps/web/components/market/CandlesPanel.tsx")
open_orders = Path("apps/web/components/market/OpenOrdersPanel.tsx")
positions = Path("apps/web/components/market/PositionsPanel.tsx")

# 1) CandlesPanel: revert alias import to known-good relative import
text = candles.read_text()
text = text.replace(
    'import { usePortalPreferences } from "@/lib/preferences/PortalPreferencesProvider";',
    'import { usePortalPreferences } from "../../src/lib/preferences/PortalPreferencesProvider";'
)
candles.write_text(text)

# 2) OpenOrdersPanel: remove any stray theme-hook import/use
for path in [open_orders, positions]:
    text = path.read_text()

    text = text.replace(
        'import { usePortalPreferences } from "@/lib/preferences/PortalPreferencesProvider";\n',
        ''
    )
    text = text.replace(
        'import { usePortalPreferences } from "../../src/lib/preferences/PortalPreferencesProvider";\n',
        ''
    )
    text = text.replace('  const { isDark } = usePortalPreferences();\n', '')
    text = text.replace('const { isDark } = usePortalPreferences();\n', '')

    path.write_text(text)

print("Patched market imports and removed stray preference-hook usage.")
PY

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ Market import recovery applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
