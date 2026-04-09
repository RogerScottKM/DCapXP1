#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

FILE="apps/web/components/market/CandlesPanel.tsx"

if [ ! -f "$FILE" ]; then
  echo "Missing $FILE"
  exit 1
fi

cp "$FILE" "${FILE}.bak.$(date +%Y%m%d%H%M%S)"

python3 - <<'PY'
from pathlib import Path
import re
import sys

path = Path("apps/web/components/market/CandlesPanel.tsx")
text = path.read_text()

# 1) Ensure hook import exists
good_import = 'import { usePortalPreferences } from "../../src/lib/preferences/PortalPreferencesProvider";'
if good_import not in text:
    text = text.replace('import { usePortalPreferences } from "@/lib/preferences/PortalPreferencesProvider";\n', '')
    lines = text.splitlines()
    insert_at = 0
    for i, line in enumerate(lines):
        if line.startswith("import "):
            insert_at = i + 1
    lines.insert(insert_at, good_import)
    text = "\n".join(lines) + ("\n" if text.endswith("\n") else "")

# 2) Ensure hook usage exists
if 'const { isDark } = usePortalPreferences();' not in text:
    text, n = re.subn(
        r'(export default function CandlesPanel\([^)]*\) \{)',
        r'\1\n  const { isDark } = usePortalPreferences();',
        text,
        count=1
    )
    if n == 0:
        print("Could not insert usePortalPreferences() into CandlesPanel")
        sys.exit(1)

# 3) Replace outer card shell with true dynamic light/dark version
text = text.replace(
    '<div className="rounded-2xl border border-white/10 bg-white/5 p-4">',
    '<div className={`rounded-2xl border p-4 ${isDark ? "border-white/10 bg-slate-900/70 shadow-none" : "border-slate-200 bg-white/80 shadow-[0_0_0_1px_rgba(15,23,42,0.04)]"}`}>'
)
text = text.replace(
    '<div className="rounded-2xl border border-slate-200 bg-white/80 p-4 shadow-[0_0_0_1px_rgba(15,23,42,0.04)] dark:border-white/10 dark:bg-white/5 dark:shadow-none">',
    '<div className={`rounded-2xl border p-4 ${isDark ? "border-white/10 bg-slate-900/70 shadow-none" : "border-slate-200 bg-white/80 shadow-[0_0_0_1px_rgba(15,23,42,0.04)]"}`}>'
)

# 4) Replace title
text = text.replace(
    '<div className="text-sm text-slate-200">Candles</div>',
    '<div className={`text-sm ${isDark ? "text-slate-200" : "font-medium text-slate-700"}`}>Candles</div>'
)
text = text.replace(
    '<div className="text-sm font-medium text-slate-700 dark:text-slate-200">Candles</div>',
    '<div className={`text-sm ${isDark ? "text-slate-200" : "font-medium text-slate-700"}`}>Candles</div>'
)

# 5) Replace timeframe button classes
text = text.replace(
    'className={`rounded-lg px-3 py-1 text-xs ${tf === x ? "bg-white/15 text-white" : "bg-white/5 text-slate-300"}`}',
    'className={`rounded-lg px-3 py-1 text-xs transition ${tf === x ? (isDark ? "bg-white/15 text-white" : "bg-slate-200 text-slate-900") : (isDark ? "bg-slate-800 text-slate-300 hover:bg-slate-700" : "bg-slate-100 text-slate-600 hover:bg-slate-200")}`}'
)
text = text.replace(
    'className={`rounded-lg px-3 py-1 text-xs transition ${tf === x ? (isDark ? "bg-white/15 text-white" : "bg-slate-200 text-slate-900") : (isDark ? "bg-white/5 text-slate-300" : "bg-slate-100 text-slate-600 hover:bg-slate-200")}`}',
    'className={`rounded-lg px-3 py-1 text-xs transition ${tf === x ? (isDark ? "bg-white/15 text-white" : "bg-slate-200 text-slate-900") : (isDark ? "bg-slate-800 text-slate-300 hover:bg-slate-700" : "bg-slate-100 text-slate-600 hover:bg-slate-200")}`}'
)

# 6) Replace fixed chart text color with theme-aware one
text = text.replace(
    'layout: { background: { color: "transparent" }, textColor: "#cbd5e1" },',
    'layout: { background: { color: "transparent" }, textColor: isDark ? "#cbd5e1" : "#475569" },'
)

# 7) If chart is only recreated on symbol, make it recreate on theme too
text = text.replace('  }, [symbol]);', '  }, [symbol, isDark]);', 1)

# 8) Give grid lines proper theme contrast if grid block exists
text = re.sub(
    r'grid:\s*\{\s*vertLines:\s*\{\s*color:\s*[^}]+\},\s*horzLines:\s*\{\s*color:\s*[^}]+\}\s*\}',
    'grid: { vertLines: { color: isDark ? "rgba(148,163,184,0.10)" : "rgba(100,116,139,0.10)" }, horzLines: { color: isDark ? "rgba(148,163,184,0.10)" : "rgba(100,116,139,0.10)" } }',
    text
)

path.write_text(text)
print("Patched CandlesPanel.tsx")
PY

echo
echo "==> Sanity check: old hardcoded candle styles should be gone ..."
rg -n 'border-white/10 bg-white/5 p-4|text-sm text-slate-200|bg-white/15 text-white|bg-white/5 text-slate-300|textColor: "#cbd5e1"' "$FILE" || true

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ CandlesPanel-only dynamic theme patch applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
