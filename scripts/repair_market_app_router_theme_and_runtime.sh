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

# ---------- CandlesPanel ----------
candles_path = Path("apps/web/components/market/CandlesPanel.tsx")
text = candles_path.read_text()

# Use alias import for the client hook
text = text.replace(
    'import { usePortalPreferences } from "../../src/lib/preferences/PortalPreferencesProvider";',
    'import { usePortalPreferences } from "@/lib/preferences/PortalPreferencesProvider";'
)
if 'import { usePortalPreferences } from "@/lib/preferences/PortalPreferencesProvider";' not in text:
    lines = text.splitlines()
    import_idx = 0
    for i, line in enumerate(lines):
        if line.startswith("import "):
            import_idx = i + 1
    lines.insert(import_idx, 'import { usePortalPreferences } from "@/lib/preferences/PortalPreferencesProvider";')
    text = "\n".join(lines) + ("\n" if text.endswith("\n") else "")

# Ensure hook line exists only once
if 'const { isDark } = usePortalPreferences();' not in text:
    text = re.sub(
        r'(export default function CandlesPanel\(\{ symbol, mode \}: \{ symbol: string; mode: Mode \}\) \{)',
        r'\1\n  const { isDark } = usePortalPreferences();',
        text,
        count=1
    )

# Theme-aware chart text
text = text.replace(
    'layout: { background: { color: "transparent" }, textColor: "#cbd5e1" },',
    'layout: { background: { color: "transparent" }, textColor: isDark ? "#cbd5e1" : "#475569" },'
)

# Recreate chart when theme changes
text = text.replace('  }, [symbol]);', '  }, [symbol, isDark]);', 1)

# Theme-safe panel shell
text = text.replace(
    '<div className="rounded-2xl border border-white/10 bg-white/5 p-4">',
    '<div className={`rounded-2xl border p-4 ${isDark ? "border-white/10 bg-white/5" : "border-slate-200 bg-white/80 shadow-[0_0_0_1px_rgba(15,23,42,0.04)]"}`}>'
)

# Theme-safe title
text = text.replace(
    '<div className="text-sm text-slate-200">Candles</div>',
    '<div className={`text-sm ${isDark ? "text-slate-200" : "font-medium text-slate-700"}`}>Candles</div>'
)

# Theme-safe timeframe buttons
text = text.replace(
    'className={`rounded-lg px-3 py-1 text-xs ${tf === x ? "bg-white/15 text-white" : "bg-white/5 text-slate-300"}`}',
    'className={`rounded-lg px-3 py-1 text-xs transition ${tf === x ? (isDark ? "bg-white/15 text-white" : "bg-slate-200 text-slate-900") : (isDark ? "bg-white/5 text-slate-300" : "bg-slate-100 text-slate-600 hover:bg-slate-200")}`}'
)

candles_path.write_text(text)

# ---------- OpenOrdersPanel ----------
open_path = Path("apps/web/components/market/OpenOrdersPanel.tsx")
text = open_path.read_text()

# remove accidental client-hook import/use if present
text = text.replace('import { usePortalPreferences } from "../../src/lib/preferences/PortalPreferencesProvider";\n', '')
text = text.replace('import { usePortalPreferences } from "@/lib/preferences/PortalPreferencesProvider";\n', '')
text = text.replace('  const { isDark } = usePortalPreferences();\n', '')

text = text.replace(
    '<div className="rounded-2xl border border-white/10 bg-white/5 p-4">',
    '<div className="rounded-2xl border border-slate-200 bg-white/80 p-4 shadow-[0_0_0_1px_rgba(15,23,42,0.04)] dark:border-white/10 dark:bg-white/5 dark:shadow-none">'
)
text = text.replace(
    '<div className="mb-2 text-sm text-slate-200">Open Orders</div>',
    '<div className="mb-2 text-sm font-medium text-slate-700 dark:text-slate-200">Open Orders</div>'
)
text = text.replace(
    '<div className="grid grid-cols-5 gap-2 pb-2 text-slate-400">',
    '<div className="grid grid-cols-5 gap-2 pb-2 text-slate-500 dark:text-slate-400">'
)
text = text.replace(
    'className="grid grid-cols-5 gap-2 border-t border-white/5 py-2 text-slate-200"',
    'className="grid grid-cols-5 gap-2 border-t border-slate-200 py-2 text-slate-700 dark:border-white/5 dark:text-slate-200"'
)
text = text.replace(
    '<div className="pt-2 text-slate-400">No open orders</div>',
    '<div className="pt-2 text-slate-500 dark:text-slate-400">No open orders</div>'
)

open_path.write_text(text)

# ---------- PositionsPanel ----------
pos_path = Path("apps/web/components/market/PositionsPanel.tsx")
text = pos_path.read_text()

# remove accidental client-hook import/use if present
text = text.replace('import { usePortalPreferences } from "../../src/lib/preferences/PortalPreferencesProvider";\n', '')
text = text.replace('import { usePortalPreferences } from "@/lib/preferences/PortalPreferencesProvider";\n', '')
text = text.replace('  const { isDark } = usePortalPreferences();\n', '')

text = text.replace(
    '<div className="rounded-2xl border border-white/10 bg-white/5 p-4">',
    '<div className="rounded-2xl border border-slate-200 bg-white/80 p-4 shadow-[0_0_0_1px_rgba(15,23,42,0.04)] dark:border-white/10 dark:bg-white/5 dark:shadow-none">'
)
text = text.replace(
    '<div className="mb-2 text-sm text-slate-200">Positions (Spot Balances)</div>',
    '<div className="mb-2 text-sm font-medium text-slate-700 dark:text-slate-200">Positions (Spot Balances)</div>'
)
text = text.replace(
    '<div className="grid grid-cols-2 gap-2 pb-2 text-slate-400">',
    '<div className="grid grid-cols-2 gap-2 pb-2 text-slate-500 dark:text-slate-400">'
)
text = text.replace(
    'className="grid grid-cols-2 gap-2 border-t border-white/5 py-2 text-slate-200"',
    'className="grid grid-cols-2 gap-2 border-t border-slate-200 py-2 text-slate-700 dark:border-white/5 dark:text-slate-200"'
)
text = text.replace(
    '<div className="pt-2 text-slate-400">No balances</div>',
    '<div className="pt-2 text-slate-500 dark:text-slate-400">No balances</div>'
)

pos_path.write_text(text)

print("Patched CandlesPanel.tsx, OpenOrdersPanel.tsx, PositionsPanel.tsx")
PY

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ Market App Router runtime + light theme repair applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
