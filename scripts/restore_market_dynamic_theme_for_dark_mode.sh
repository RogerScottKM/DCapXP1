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

# 1) Ensure the preferences hook import exists and uses the known-good path
good_import = 'import { usePortalPreferences } from "../../src/lib/preferences/PortalPreferencesProvider";'
if good_import not in text:
    # remove any stray old import first
    text = text.replace('import { usePortalPreferences } from "@/lib/preferences/PortalPreferencesProvider";\n', '')
    text = text.replace('import { usePortalPreferences } from "../../src/lib/preferences/PortalPreferencesProvider";\n', '')
    lines = text.splitlines()
    insert_at = 0
    for i, line in enumerate(lines):
        if line.startswith("import "):
            insert_at = i + 1
    lines.insert(insert_at, good_import)
    text = "\n".join(lines) + ("\n" if text.endswith("\n") else "")

# 2) Ensure component reads isDark exactly once
if 'const { isDark } = usePortalPreferences();' not in text:
    text, n = re.subn(
        r'(export default function CandlesPanel\([^)]*\) \{)',
        r'\1\n  const { isDark } = usePortalPreferences();',
        text,
        count=1
    )
    if n == 0:
        print("Could not insert usePortalPreferences hook into CandlesPanel")
        sys.exit(1)

# 3) Make the outer panel truly dual-theme
patterns = [
    r'<div className="rounded-2xl border border-slate-200 bg-white/80 p-4 shadow-\[0_0_0_1px_rgba\(15,23,42,0\.04\)\] dark:border-white/10 dark:bg-white/5 dark:shadow-none">',
    r'<div className="rounded-2xl border border-white/10 bg-white/5 p-4">',
    r'<div className=\{`rounded-2xl border p-4 \$\{isDark \? "border-white/10 bg-white/5" : "border-slate-200 bg-white/80 shadow-\[0_0_0_1px_rgba\(15,23,42,0\.04\)\]"\}`\}>',
]
replacement = '<div className={`rounded-2xl border p-4 ${isDark ? "border-white/10 bg-slate-900/70 shadow-none" : "border-slate-200 bg-white/80 shadow-[0_0_0_1px_rgba(15,23,42,0.04)]"}`}>'
for pat in patterns:
    text, _ = re.subn(pat, replacement, text)

# 4) Candles title
text = text.replace(
    '<div className="text-sm font-medium text-slate-700 dark:text-slate-200">Candles</div>',
    '<div className={`text-sm ${isDark ? "text-slate-200" : "font-medium text-slate-700"}`}>Candles</div>'
)
text = text.replace(
    '<div className="text-sm text-slate-200">Candles</div>',
    '<div className={`text-sm ${isDark ? "text-slate-200" : "font-medium text-slate-700"}`}>Candles</div>'
)

# 5) Timeframe selector buttons
text = text.replace(
    'className={`rounded-lg px-3 py-1 text-xs transition ${tf === x ? (isDark ? "bg-white/15 text-white" : "bg-slate-200 text-slate-900") : (isDark ? "bg-white/5 text-slate-300" : "bg-slate-100 text-slate-600 hover:bg-slate-200")}`}',
    'className={`rounded-lg px-3 py-1 text-xs transition ${tf === x ? (isDark ? "bg-white/15 text-white" : "bg-slate-200 text-slate-900") : (isDark ? "bg-slate-800 text-slate-300 hover:bg-slate-700" : "bg-slate-100 text-slate-600 hover:bg-slate-200")}`}'
)
text = text.replace(
    'className={`rounded-lg px-3 py-1 text-xs ${tf === x ? "bg-white/15 text-white" : "bg-white/5 text-slate-300"}`}',
    'className={`rounded-lg px-3 py-1 text-xs transition ${tf === x ? (isDark ? "bg-white/15 text-white" : "bg-slate-200 text-slate-900") : (isDark ? "bg-slate-800 text-slate-300 hover:bg-slate-700" : "bg-slate-100 text-slate-600 hover:bg-slate-200")}`}'
)

# 6) Chart layout text color
text = re.sub(
    r'layout:\s*\{\s*background:\s*\{\s*color:\s*"transparent"\s*\},\s*textColor:\s*[^}]+\}',
    'layout: { background: { color: "transparent" }, textColor: isDark ? "#cbd5e1" : "#475569" }',
    text
)

# 7) If grid block exists, make it theme-aware
text = re.sub(
    r'grid:\s*\{\s*vertLines:\s*\{\s*color:\s*[^}]+\},\s*horzLines:\s*\{\s*color:\s*[^}]+\}\s*\}',
    'grid: { vertLines: { color: isDark ? "rgba(148,163,184,0.10)" : "rgba(100,116,139,0.10)" }, horzLines: { color: isDark ? "rgba(148,163,184,0.10)" : "rgba(100,116,139,0.10)" } }',
    text
)

# 8) If no grid block at all, inject one after layout
if 'grid:' not in text and 'layout: { background: { color: "transparent" }, textColor: isDark ? "#cbd5e1" : "#475569" }' in text:
    text = text.replace(
        'layout: { background: { color: "transparent" }, textColor: isDark ? "#cbd5e1" : "#475569" },',
        'layout: { background: { color: "transparent" }, textColor: isDark ? "#cbd5e1" : "#475569" },\n      grid: { vertLines: { color: isDark ? "rgba(148,163,184,0.10)" : "rgba(100,116,139,0.10)" }, horzLines: { color: isDark ? "rgba(148,163,184,0.10)" : "rgba(100,116,139,0.10)" } },'
    )

# 9) Recreate chart when theme changes
text = text.replace('  }, [symbol]);', '  }, [symbol, isDark]);', 1)

path.write_text(text)
print("Patched CandlesPanel.tsx")
PY

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ Dynamic market theming restored for CandlesPanel."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
