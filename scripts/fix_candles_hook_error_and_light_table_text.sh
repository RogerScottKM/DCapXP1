#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

APP_FILE="apps/web/pages/_app.tsx"
CANDLES_FILE="apps/web/components/market/CandlesPanel.tsx"

if [ ! -f "$APP_FILE" ]; then
  echo "Missing $APP_FILE"
  exit 1
fi

if [ ! -f "$CANDLES_FILE" ]; then
  echo "Missing $CANDLES_FILE"
  exit 1
fi

backup "$APP_FILE"
backup "$CANDLES_FILE"

echo "==> Strengthening light-mode market text readability ..."
cat > "$APP_FILE" <<'EOF'
import type { AppProps } from "next/app";
import { PortalPreferencesProvider } from "../src/lib/preferences/PortalPreferencesProvider";

export default function App({ Component, pageProps }: AppProps) {
  return (
    <PortalPreferencesProvider>
      <Component {...pageProps} />
      <style jsx global>{`
        html[data-dcapx-theme="light"] body {
          background: #e5e7eb;
          color: #0f172a;
        }

        html[data-dcapx-theme="light"] table th {
          color: #475569 !important;
          opacity: 1 !important;
        }

        html[data-dcapx-theme="light"] table td {
          color: #0f172a !important;
          opacity: 1 !important;
        }

        html[data-dcapx-theme="light"] table td *,
        html[data-dcapx-theme="light"] table th * {
          opacity: 1 !important;
        }

        html[data-dcapx-theme="light"] .text-slate-300,
        html[data-dcapx-theme="light"] .text-slate-400,
        html[data-dcapx-theme="light"] .text-slate-500,
        html[data-dcapx-theme="light"] .text-white\\/40,
        html[data-dcapx-theme="light"] .text-white\\/50,
        html[data-dcapx-theme="light"] .text-white\\/60,
        html[data-dcapx-theme="light"] .text-white\\/70 {
          color: #334155 !important;
          opacity: 1 !important;
        }

        html[data-dcapx-theme="light"] .opacity-40,
        html[data-dcapx-theme="light"] .opacity-50,
        html[data-dcapx-theme="light"] .opacity-60,
        html[data-dcapx-theme="light"] .opacity-70 {
          opacity: 1 !important;
        }

        html[data-dcapx-theme="light"] .text-emerald-300,
        html[data-dcapx-theme="light"] .text-emerald-400,
        html[data-dcapx-theme="light"] .text-green-400 {
          color: #047857 !important;
        }

        html[data-dcapx-theme="light"] .text-rose-300,
        html[data-dcapx-theme="light"] .text-rose-400,
        html[data-dcapx-theme="light"] .text-red-400 {
          color: #be123c !important;
        }

        html[data-dcapx-theme="light"] input,
        html[data-dcapx-theme="light"] select,
        html[data-dcapx-theme="light"] button {
          color: inherit;
        }
      `}</style>
    </PortalPreferencesProvider>
  );
}
EOF

echo "==> Repairing CandlesPanel.tsx ..."
python3 - <<'PY'
from pathlib import Path
import re
import sys

path = Path("apps/web/components/market/CandlesPanel.tsx")
text = path.read_text()

old_hook = 'const displayCandles = useMemo(() => normalizeSyntheticRvaiCandles(rawCandles as any[], symbol as string), [rawCandles, symbol]);'
new_plain = 'const displayCandles = normalizeSyntheticRvaiCandles(rawCandles as any[], symbol as string);'

if old_hook in text:
    text = text.replace(old_hook, new_plain)
else:
    text = re.sub(
        r'const\s+displayCandles\s*=\s*useMemo\(\(\)\s*=>\s*normalizeSyntheticRvaiCandles\(rawCandles as any\[\], symbol as string\)\s*,\s*\[rawCandles,\s*symbol\]\s*\);',
        new_plain,
        text
    )

# Make sure the normalized chart uses the adjusted candles, not raw candles.
text = text.replace(
    'const candles = normalizeCandles(rawCandles);',
    'const candles = normalizeCandles(displayCandles);'
)

path.write_text(text)
print("Patched CandlesPanel.tsx")
PY

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ Candles hook error + light-mode table readability fix applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
