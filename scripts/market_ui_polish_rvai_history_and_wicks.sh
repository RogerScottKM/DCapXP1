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

echo "==> Rewriting _app.tsx with market light-mode readability overrides ..."
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

        html[data-dcapx-theme="light"] .text-slate-300 {
          color: #475569 !important;
        }

        html[data-dcapx-theme="light"] .text-slate-400 {
          color: #334155 !important;
        }

        html[data-dcapx-theme="light"] .text-slate-500 {
          color: #334155 !important;
        }

        html[data-dcapx-theme="light"] .text-white\\/50,
        html[data-dcapx-theme="light"] .text-white\\/60,
        html[data-dcapx-theme="light"] .text-white\\/70 {
          color: #334155 !important;
          opacity: 1 !important;
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

echo "==> Patching CandlesPanel.tsx for RVAI history + wick normalization ..."
python3 - <<'PY'
from pathlib import Path
import re
import sys

path = Path("apps/web/components/market/CandlesPanel.tsx")
text = path.read_text()

helper_block = r'''
const RVAI_VISUAL_HISTORY_BARS = 160;
const RVAI_WICK_CAP_PCT = 0.018;
const RVAI_WICK_BODY_MULTIPLIER = 1.25;
const RVAI_PREHISTORY_DRIFT_PCT = 0.0007;

function candlePeriodToMs(period?: string): number {
  switch ((period ?? "").trim()) {
    case "1m":
      return 60_000;
    case "5m":
      return 5 * 60_000;
    case "15m":
      return 15 * 60_000;
    case "1h":
      return 60 * 60_000;
    case "4h":
      return 4 * 60 * 60_000;
    case "1d":
      return 24 * 60 * 60_000;
    default:
      return 5 * 60_000;
  }
}

function toFiniteNumber(value: any, fallback: number): number {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function readTimeValue(candle: any): any {
  return candle?.time ?? candle?.t ?? candle?.timestamp ?? null;
}

function timeToMs(value: any): number | null {
  if (typeof value === "number") {
    if (value > 1_000_000_000_000) return value;
    if (value > 1_000_000_000) return value * 1000;
    return value;
  }

  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  return null;
}

function writeTimeLike(template: any, ms: number): any {
  const source = readTimeValue(template);

  if (typeof source === "number") {
    if (source > 1_000_000_000_000) return ms;
    if (source > 1_000_000_000) return Math.floor(ms / 1000);
    return Math.floor(ms / 1000);
  }

  if (typeof source === "string") {
    return new Date(ms).toISOString();
  }

  return ms;
}

function readOHLC(candle: any) {
  const open = toFiniteNumber(candle?.open ?? candle?.o, 0);
  const high = toFiniteNumber(candle?.high ?? candle?.h, open);
  const low = toFiniteNumber(candle?.low ?? candle?.l, open);
  const close = toFiniteNumber(candle?.close ?? candle?.c, open);

  return { open, high, low, close };
}

function writeOHLC(template: any, open: number, high: number, low: number, close: number) {
  const next = { ...template };

  if ("open" in next || !("o" in next)) next.open = open;
  else next.o = open;

  if ("high" in next || !("h" in next)) next.high = high;
  else next.h = high;

  if ("low" in next || !("l" in next)) next.low = low;
  else next.l = low;

  if ("close" in next || !("c" in next)) next.close = close;
  else next.c = close;

  if ("time" in next || !("t" in next)) next.time = writeTimeLike(template, timeToMs(readTimeValue(template)) ?? Date.now());
  else next.t = writeTimeLike(template, timeToMs(readTimeValue(template)) ?? Date.now());

  return next;
}

function clampRvaiWicks(candle: any): any {
  const { open, high, low, close } = readOHLC(candle);
  const reference = Math.max(open, close, 0.0001);
  const body = Math.max(Math.abs(close - open), reference * 0.00045);
  const maxWick = Math.max(reference * RVAI_WICK_CAP_PCT, body * RVAI_WICK_BODY_MULTIPLIER);

  const top = Math.max(open, close);
  const bottom = Math.min(open, close);

  const adjustedHigh = Math.min(high, top + maxWick);
  const adjustedLow = Math.max(0.000001, Math.max(low, bottom - maxWick));

  const next = { ...candle };

  if ("high" in next || !("h" in next)) next.high = adjustedHigh;
  else next.h = adjustedHigh;

  if ("low" in next || !("l" in next)) next.low = adjustedLow;
  else next.l = adjustedLow;

  return next;
}

function prependRvaiHistory(candles: any[], period?: string): any[] {
  if (!candles.length) return candles;
  if (candles.length >= RVAI_VISUAL_HISTORY_BARS) return candles;

  const first = candles[0];
  const firstMs = timeToMs(readTimeValue(first));
  if (!firstMs) return candles;

  const stepMs = candlePeriodToMs(period);
  const missing = RVAI_VISUAL_HISTORY_BARS - candles.length;

  const firstOhlc = readOHLC(first);
  let price = Math.max(firstOhlc.open || firstOhlc.close || 0.1, 0.0001);

  const extras: any[] = [];

  for (let i = missing; i >= 1; i -= 1) {
    const ms = firstMs - stepMs * i;
    const wobble = Math.sin(i * 0.77) * price * RVAI_PREHISTORY_DRIFT_PCT;
    const open = price;
    const close = Math.max(0.0001, price + wobble * 0.55);
    const body = Math.max(Math.abs(close - open), price * 0.00035);
    const wick = Math.max(price * 0.0015, body * 0.95);

    const high = Math.max(open, close) + wick;
    const low = Math.max(0.0001, Math.min(open, close) - wick);

    const template = { ...first };

    if ("time" in template || !("t" in template)) template.time = writeTimeLike(first, ms);
    else template.t = writeTimeLike(first, ms);

    if ("open" in template || !("o" in template)) template.open = open;
    else template.o = open;

    if ("high" in template || !("h" in template)) template.high = high;
    else template.h = high;

    if ("low" in template || !("l" in template)) template.low = low;
    else template.l = low;

    if ("close" in template || !("c" in template)) template.close = close;
    else template.c = close;

    extras.push(template);
    price = close;
  }

  return [...extras, ...candles];
}

function normalizeSyntheticRvaiCandles(
  candles: any[],
  symbol: string,
  period?: string
): any[] {
  if (String(symbol) !== "RVAI-USD") return candles;
  if (!Array.isArray(candles) || candles.length === 0) return candles;

  const normalized = candles.map((candle) => clampRvaiWicks(candle));
  return prependRvaiHistory(normalized, period);
}
'''

if "normalizeSyntheticRvaiCandles" not in text:
    # insert helper block after imports
    import_matches = list(re.finditer(r"^import .*?;$", text, flags=re.MULTILINE))
    if not import_matches:
        print("Could not find import section in CandlesPanel.tsx")
        sys.exit(1)
    last_import = import_matches[-1]
    insert_at = last_import.end()
    text = text[:insert_at] + "\n" + helper_block + "\n" + text[insert_at:]

# Find rawCandles declaration
m = re.search(r"const\s+rawCandles\s*=\s*useMemo\([\s\S]*?\n\s*\);", text)
if not m:
    m = re.search(r"const\s+rawCandles\s*=\s*[^;]+;", text)

if not m:
    print("Could not find rawCandles declaration in CandlesPanel.tsx")
    print("Please paste:")
    print("  sed -n '1,260p' apps/web/components/market/CandlesPanel.tsx")
    sys.exit(1)

block = m.group(0)
if "const displayCandles =" not in text:
    insertion = block + '\n\n  const displayCandles = useMemo(() => normalizeSyntheticRvaiCandles(rawCandles as any[], symbol as string, period as string | undefined), [rawCandles, symbol, period]);'
    text = text.replace(block, insertion, 1)

# Replace common usages
replacements = [
    ("rawCandles.map(", "displayCandles.map("),
    ("rawCandles?.map(", "displayCandles?.map("),
    ("rawCandles.length", "displayCandles.length"),
    ("rawCandles[", "displayCandles["),
]

for old, new in replacements:
    text = text.replace(old, new)

# But restore declaration if it got touched accidentally
text = text.replace("const displayCandles = useMemo(() => normalizeSyntheticRvaiCandles(displayCandles as any[], symbol as string, period as string | undefined), [displayCandles, symbol, period]);",
                    "const displayCandles = useMemo(() => normalizeSyntheticRvaiCandles(rawCandles as any[], symbol as string, period as string | undefined), [rawCandles, symbol, period]);")

path.write_text(text)
print("Patched CandlesPanel.tsx")
PY

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ Market UI polish + RVAI visual candle tuning applied."
echo
echo "This patch does three things:"
echo "  1) darkens light-mode table text"
echo "  2) gives RVAI-USD a longer visual candle history"
echo "  3) caps RVAI wick extremes to a more realistic ratio"
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
