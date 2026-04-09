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

# 1) Remove PortalPreferences hook import if present
text = text.replace(
    'import { usePortalPreferences } from "../../src/lib/preferences/PortalPreferencesProvider";\n',
    ''
)
text = text.replace(
    'import { usePortalPreferences } from "@/lib/preferences/PortalPreferencesProvider";\n',
    ''
)

# 2) Replace hook usage with DOM-synced theme state
old = '  const { isDark } = usePortalPreferences();'
new = '''  const [isDark, setIsDark] = useState(false);

  useEffect(() => {
    const readTheme = () => {
      if (typeof document === "undefined") return false;
      const el = document.documentElement;
      return el.dataset.dcapxTheme === "dark" || el.classList.contains("dark");
    };

    setIsDark(readTheme());

    if (typeof MutationObserver === "undefined" || typeof document === "undefined") {
      return;
    }

    const observer = new MutationObserver(() => {
      setIsDark(readTheme());
    });

    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["class", "data-dcapx-theme"],
    });

    return () => observer.disconnect();
  }, []);'''
if old in text:
    text = text.replace(old, new)
else:
    # If old line was already removed, inject after component open
    if 'const [isDark, setIsDark] = useState(false);' not in text:
        text, n = re.subn(
            r'(export default function CandlesPanel\([^)]*\) \{)',
            r'\1\n' + new,
            text,
            count=1
        )
        if n == 0:
            print("Could not inject DOM theme state block.")
            sys.exit(1)

# 3) Force explicit chart background colors
text = re.sub(
    r'layout:\s*\{\s*background:\s*\{\s*color:\s*"transparent"\s*\},\s*textColor:\s*isDark\s*\?\s*"#cbd5e1"\s*:\s*"#475569"\s*\},',
    '''layout: {
      background: { color: isDark ? "#020617" : "#f8fafc" },
      textColor: isDark ? "#cbd5e1" : "#475569",
    },''',
    text
)

# 4) Recreate chart when theme changes
text = text.replace(
    '  }, [symbol, tf, mode]);',
    '  }, [symbol, tf, mode, isDark]);'
)

# 5) Make host div explicit too
text = text.replace(
    '<div ref={ref} className={isDark ? "rounded-xl bg-slate-950" : "rounded-xl bg-slate-50"} />',
    '<div ref={ref} className={isDark ? "rounded-xl bg-slate-950" : "rounded-xl bg-slate-50"} />'
)
text = text.replace(
    '<div ref={ref} className={isDark ? "rounded-xl bg-slate-950/70" : "rounded-xl bg-slate-50"} />',
    '<div ref={ref} className={isDark ? "rounded-xl bg-slate-950" : "rounded-xl bg-slate-50"} />'
)
if '<div ref={ref}' in text and 'className=' not in text[text.find('<div ref={ref}'):text.find('/>', text.find('<div ref={ref}'))]:
    text = text.replace('<div ref={ref} />', '<div ref={ref} className={isDark ? "rounded-xl bg-slate-950" : "rounded-xl bg-slate-50"} />')

path.write_text(text)
print("Patched CandlesPanel.tsx")
PY

echo
echo "==> Confirm key lines ..."
sed -n '1,40p' "$FILE" || true
echo
sed -n '245,260p' "$FILE" || true
echo
sed -n '585,600p' "$FILE" || true

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ CandlesPanel theme sync patch applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
