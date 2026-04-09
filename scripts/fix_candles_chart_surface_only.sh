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

# 1) Ensure isDark hook exists once
if 'const { isDark } = usePortalPreferences();' not in text:
    text, n = re.subn(
        r'(export default function CandlesPanel\([^)]*\) \{)',
        r'\1\n  const { isDark } = usePortalPreferences();',
        text,
        count=1
    )
    if n == 0:
        print("Could not insert usePortalPreferences hook")
        sys.exit(1)

# 2) Replace the chart layout block with explicit dark/light surface colors
old_layout = 'layout: { background: { color: "transparent" }, textColor: "#cbd5e1" },'
new_layout = '''layout: {
        background: { color: isDark ? "#0b1220" : "#f8fafc" },
        textColor: isDark ? "#cbd5e1" : "#475569",
      },'''
if old_layout in text:
    text = text.replace(old_layout, new_layout)
else:
    text = re.sub(
        r'layout:\s*\{\s*background:\s*\{\s*color:\s*"transparent"\s*\},\s*textColor:\s*"#cbd5e1"\s*\},',
        new_layout,
        text
    )

# 3) Make grid lines theme-aware too
if 'grid:' in text:
    text = re.sub(
        r'grid:\s*\{\s*vertLines:\s*\{\s*color:\s*[^}]+\},\s*horzLines:\s*\{\s*color:\s*[^}]+\}\s*\},',
        '''grid: {
        vertLines: { color: isDark ? "rgba(148,163,184,0.10)" : "rgba(100,116,139,0.10)" },
        horzLines: { color: isDark ? "rgba(148,163,184,0.10)" : "rgba(100,116,139,0.10)" },
      },''',
        text
    )
else:
    text = text.replace(
        new_layout,
        new_layout + '\n      grid: {\n        vertLines: { color: isDark ? "rgba(148,163,184,0.10)" : "rgba(100,116,139,0.10)" },\n        horzLines: { color: isDark ? "rgba(148,163,184,0.10)" : "rgba(100,116,139,0.10)" },\n      },'
    )

# 4) Recreate chart when theme changes
text = text.replace('  }, [symbol, tf, mode]);', '  }, [symbol, tf, mode, isDark]);')
text = text.replace('  }, [symbol, tf, mode]);', '  }, [symbol, tf, mode, isDark]);')

# 5) Theme the actual host div, not just the outer card
text = text.replace(
    '<div ref={ref} />',
    '<div ref={ref} className={isDark ? "rounded-xl bg-slate-950/70" : "rounded-xl bg-slate-50"} />'
)

path.write_text(text)
print("Patched CandlesPanel.tsx")
PY

echo
echo "==> Sanity check ..."
rg -n 'background: \{ color:|textColor:|grid:|<div ref=\{ref\}' "$FILE" || true

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ Candles chart surface patch applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
