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

path = Path("apps/web/components/market/CandlesPanel.tsx")
text = path.read_text()

old_layout = 'layout: { background: { color: "transparent" }, textColor: isDark ? "#cbd5e1" : "#475569" },'
new_layout = '''layout: {
      background: { color: isDark ? "#020617" : "#f8fafc" },
      textColor: isDark ? "#cbd5e1" : "#475569",
    },'''

if old_layout in text:
    text = text.replace(old_layout, new_layout)
else:
    print("Could not find exact layout line to replace.")
    print("Please paste: sed -n '235,265p' apps/web/components/market/CandlesPanel.tsx")
    raise SystemExit(1)

old_deps = '  }, [symbol, tf, mode]);'
new_deps = '  }, [symbol, tf, mode, isDark]);'

if old_deps in text:
    text = text.replace(old_deps, new_deps, 1)
else:
    print("Could not find exact effect dependency line to replace.")
    print("Please paste: sed -n '555,575p' apps/web/components/market/CandlesPanel.tsx")
    raise SystemExit(1)

# Make the host div background fully explicit too
old_host = '<div ref={ref} className={isDark ? "rounded-xl bg-slate-950/70" : "rounded-xl bg-slate-50"} />'
new_host = '<div ref={ref} className={isDark ? "rounded-xl bg-slate-950" : "rounded-xl bg-slate-50"} />'
text = text.replace(old_host, new_host)

path.write_text(text)
print("Patched CandlesPanel.tsx")
PY

echo
echo "==> Confirm patch ..."
sed -n '245,260p' "$FILE" || true
echo
sed -n '585,600p' "$FILE" || true

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ CandlesPanel dark/light chart surface patch applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
