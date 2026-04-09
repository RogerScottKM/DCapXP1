#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

OPEN="apps/web/components/market/OpenOrdersPanel.tsx"
POS="apps/web/components/market/PositionsPanel.tsx"

for f in "$OPEN" "$POS"; do
  if [ ! -f "$f" ]; then
    echo "Missing $f"
    exit 1
  fi
  backup "$f"
done

python3 - <<'PY'
from pathlib import Path

files = [
    Path("apps/web/components/market/OpenOrdersPanel.tsx"),
    Path("apps/web/components/market/PositionsPanel.tsx"),
]

replacements = {
    'import { usePortalPreferences } from "@/lib/preferences/PortalPreferencesProvider";\n': '',
    'import { usePortalPreferences } from "../../src/lib/preferences/PortalPreferencesProvider";\n': '',
    '  const { isDark } = usePortalPreferences();\n': '',
    'const { isDark } = usePortalPreferences();\n': '',

    '<div className={`rounded-2xl border p-4 ${isDark ? "border-white/10 bg-white/5" : "border-slate-200 bg-white/80 shadow-[0_0_0_1px_rgba(15,23,42,0.04)]"}`}>':
    '<div className="rounded-2xl border border-slate-200 bg-white/80 p-4 shadow-[0_0_0_1px_rgba(15,23,42,0.04)] dark:border-white/10 dark:bg-white/5 dark:shadow-none">',

    '<div className={`mb-2 text-sm ${isDark ? "text-slate-200" : "font-medium text-slate-700"}`}>Open Orders</div>':
    '<div className="mb-2 text-sm font-medium text-slate-700 dark:text-slate-200">Open Orders</div>',

    '<div className={`mb-2 text-sm ${isDark ? "text-slate-200" : "font-medium text-slate-700"}`}>Positions (Spot Balances)</div>':
    '<div className="mb-2 text-sm font-medium text-slate-700 dark:text-slate-200">Positions (Spot Balances)</div>',

    '<div className={`grid grid-cols-5 gap-2 pb-2 ${isDark ? "text-slate-400" : "text-slate-500"}`}>':
    '<div className="grid grid-cols-5 gap-2 pb-2 text-slate-500 dark:text-slate-400">',

    '<div className={`grid grid-cols-2 gap-2 pb-2 ${isDark ? "text-slate-400" : "text-slate-500"}`}>':
    '<div className="grid grid-cols-2 gap-2 pb-2 text-slate-500 dark:text-slate-400">',

    'className={`grid grid-cols-5 gap-2 border-t py-2 ${isDark ? "border-white/5 text-slate-200" : "border-slate-200 text-slate-700"}`}':
    'className="grid grid-cols-5 gap-2 border-t border-slate-200 py-2 text-slate-700 dark:border-white/5 dark:text-slate-200"',

    'className={`grid grid-cols-2 gap-2 border-t py-2 ${isDark ? "border-white/5 text-slate-200" : "border-slate-200 text-slate-700"}`}':
    'className="grid grid-cols-2 gap-2 border-t border-slate-200 py-2 text-slate-700 dark:border-white/5 dark:text-slate-200"',

    '<div className={`pt-2 ${isDark ? "text-slate-400" : "text-slate-500"}`}>No open orders</div>':
    '<div className="pt-2 text-slate-500 dark:text-slate-400">No open orders</div>',

    '<div className={`pt-2 ${isDark ? "text-slate-400" : "text-slate-500"}`}>No balances</div>':
    '<div className="pt-2 text-slate-500 dark:text-slate-400">No balances</div>',
}

for path in files:
    text = path.read_text()
    for old, new in replacements.items():
        text = text.replace(old, new)
    path.write_text(text)

print("Patched OpenOrdersPanel.tsx and PositionsPanel.tsx")
PY

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ Static market panel theme classes applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"

