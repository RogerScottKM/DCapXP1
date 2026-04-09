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
OPEN_ORDERS="apps/web/components/market/OpenOrdersPanel.tsx"
POSITIONS="apps/web/components/market/PositionsPanel.tsx"

for f in "$CANDLES" "$OPEN_ORDERS" "$POSITIONS"; do
  if [ ! -f "$f" ]; then
    echo "Missing $f"
    exit 1
  fi
  backup "$f"
done

python3 - <<'PY'
from pathlib import Path
import re
import sys

def ensure_import(text: str) -> str:
    target = 'import { usePortalPreferences } from "../../src/lib/preferences/PortalPreferencesProvider";'
    if target in text:
        return text
    lines = text.splitlines()
    insert_at = 0
    for i, line in enumerate(lines):
        if line.startswith("import "):
            insert_at = i + 1
    lines.insert(insert_at, target)
    return "\n".join(lines) + ("\n" if text.endswith("\n") else "")

def inject_hook(text: str, component_name: str) -> str:
    pattern = rf'(export default function {component_name}\([^)]*\) \{{)'
    repl = rf'\1\n  const {{ isDark }} = usePortalPreferences();'
    new_text, n = re.subn(pattern, repl, text, count=1)
    return new_text if n else text

# ---------- CandlesPanel ----------
candles_path = Path("apps/web/components/market/CandlesPanel.tsx")
text = candles_path.read_text()

text = ensure_import(text)
text = inject_hook(text, "CandlesPanel")

text = text.replace(
    'layout: { background: { color: "transparent" }, textColor: "#cbd5e1" },',
    'layout: { background: { color: "transparent" }, textColor: isDark ? "#cbd5e1" : "#475569" },'
)

# recreate chart when theme changes
text = text.replace('  }, [symbol]);', '  }, [symbol, isDark]);', 1)

text = text.replace(
    '<div className="rounded-2xl border border-white/10 bg-white/5 p-4">',
    '<div className={`rounded-2xl border p-4 ${isDark ? "border-white/10 bg-white/5" : "border-slate-200 bg-white/80 shadow-[0_0_0_1px_rgba(15,23,42,0.04)]"}`}>'
)

text = text.replace(
    '<div className="text-sm text-slate-200">Candles</div>',
    '<div className={`text-sm ${isDark ? "text-slate-200" : "font-medium text-slate-700"}`}>Candles</div>'
)

text = text.replace(
    'className={`rounded-lg px-3 py-1 text-xs ${tf === x ? "bg-white/15 text-white" : "bg-white/5 text-slate-300"}`}',
    'className={`rounded-lg px-3 py-1 text-xs transition ${tf === x ? (isDark ? "bg-white/15 text-white" : "bg-slate-200 text-slate-900") : (isDark ? "bg-white/5 text-slate-300" : "bg-slate-100 text-slate-600 hover:bg-slate-200")}`}'
)

candles_path.write_text(text)

# ---------- OpenOrdersPanel ----------
oo_path = Path("apps/web/components/market/OpenOrdersPanel.tsx")
text = oo_path.read_text()

text = ensure_import(text)
text = inject_hook(text, "OpenOrdersPanel")

text = text.replace(
    '<div className="rounded-2xl border border-white/10 bg-white/5 p-4">',
    '<div className={`rounded-2xl border p-4 ${isDark ? "border-white/10 bg-white/5" : "border-slate-200 bg-white/80 shadow-[0_0_0_1px_rgba(15,23,42,0.04)]"}`}>'
)

text = text.replace(
    '<div className="mb-2 text-sm text-slate-200">Open Orders</div>',
    '<div className={`mb-2 text-sm ${isDark ? "text-slate-200" : "font-medium text-slate-700"}`}>Open Orders</div>'
)

text = text.replace(
    '<div className="grid grid-cols-5 gap-2 pb-2 text-slate-400">',
    '<div className={`grid grid-cols-5 gap-2 pb-2 ${isDark ? "text-slate-400" : "text-slate-500"}`}>'
)

text = text.replace(
    'className="grid grid-cols-5 gap-2 border-t border-white/5 py-2 text-slate-200"',
    'className={`grid grid-cols-5 gap-2 border-t py-2 ${isDark ? "border-white/5 text-slate-200" : "border-slate-200 text-slate-700"}`}'
)

text = text.replace(
    '<div className="pt-2 text-slate-400">No open orders</div>',
    '<div className={`pt-2 ${isDark ? "text-slate-400" : "text-slate-500"}`}>No open orders</div>'
)

oo_path.write_text(text)

# ---------- PositionsPanel ----------
pos_path = Path("apps/web/components/market/PositionsPanel.tsx")
text = pos_path.read_text()

text = ensure_import(text)
text = inject_hook(text, "PositionsPanel")

text = text.replace(
    '<div className="rounded-2xl border border-white/10 bg-white/5 p-4">',
    '<div className={`rounded-2xl border p-4 ${isDark ? "border-white/10 bg-white/5" : "border-slate-200 bg-white/80 shadow-[0_0_0_1px_rgba(15,23,42,0.04)]"}`}>'
)

text = text.replace(
    '<div className="mb-2 text-sm text-slate-200">Positions (Spot Balances)</div>',
    '<div className={`mb-2 text-sm ${isDark ? "text-slate-200" : "font-medium text-slate-700"}`}>Positions (Spot Balances)</div>'
)

text = text.replace(
    '<div className="grid grid-cols-2 gap-2 pb-2 text-slate-400">',
    '<div className={`grid grid-cols-2 gap-2 pb-2 ${isDark ? "text-slate-400" : "text-slate-500"}`}>'
)

text = text.replace(
    'className="grid grid-cols-2 gap-2 border-t border-white/5 py-2 text-slate-200"',
    'className={`grid grid-cols-2 gap-2 border-t py-2 ${isDark ? "border-white/5 text-slate-200" : "border-slate-200 text-slate-700"}`}'
)

text = text.replace(
    '<div className="pt-2 text-slate-400">No balances</div>',
    '<div className={`pt-2 ${isDark ? "text-slate-400" : "text-slate-500"}`}>No balances</div>'
)

pos_path.write_text(text)

print("Patched CandlesPanel.tsx, OpenOrdersPanel.tsx, PositionsPanel.tsx")
PY

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ Left-side market light-mode patch applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
