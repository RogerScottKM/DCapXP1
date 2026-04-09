#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

echo "==> Backing up likely files..."
backup apps/api/src/app.ts
backup apps/web/app/markets/[symbol]/page.tsx
backup apps/web/app/exchange/[symbol]/page.tsx
backup apps/web/src/features/markets/MarketPage.tsx
backup apps/web/src/features/exchange/ExchangeMarketPage.tsx

echo "==> Patching apps/api/src/app.ts ..."
python3 - <<'PY'
from pathlib import Path

p = Path("apps/api/src/app.ts")
text = p.read_text()

# Ensure stream import exists
if 'import streamRoutes from "./routes/stream";' not in text:
    lines = text.splitlines()
    insert_at = 0
    for i, ln in enumerate(lines):
        if ln.startswith("import "):
            insert_at = i + 1
    lines.insert(insert_at, 'import streamRoutes from "./routes/stream";')
    text = "\n".join(lines)

mount_block = """
// stream compatibility mounts
app.use("/v1/stream", streamRoutes);
app.use("/api/v1/stream", streamRoutes);
""".strip()

if 'app.use("/v1/stream", streamRoutes);' not in text:
    marker = "// Global error handler"
    if marker in text:
        text = text.replace(marker, mount_block + "\n\n" + marker)
    else:
        text += "\n\n" + mount_block + "\n"

p.write_text(text)
print("Patched apps/api/src/app.ts")
PY

echo "==> Trying to patch market badge file ..."
python3 - <<'PY'
from pathlib import Path
import re
import sys

candidates = [
    Path("apps/web/app/markets/[symbol]/page.tsx"),
    Path("apps/web/app/exchange/[symbol]/page.tsx"),
    Path("apps/web/src/features/markets/MarketPage.tsx"),
    Path("apps/web/src/features/exchange/ExchangeMarketPage.tsx"),
]

target = None
text = None

for p in candidates:
    if p.exists():
        t = p.read_text()
        if "ERROR" in t and ("Mid:" in t or "Last:" in t):
            target = p
            text = t
            break

if not target:
    print("Could not auto-find the market UI file that renders the ERROR badge.")
    print("Please send me the file path if web build later fails to show SNAPSHOT.")
    sys.exit(0)

if "const connectionLabel =" in text:
    print(f"{target} already appears patched; skipping.")
    sys.exit(0)

# Detect useful variable names
state_names = set(re.findall(r'const\s*\[\s*(\w+)\s*,\s*set\w+\s*\]\s*=\s*useState', text))
all_words = set(re.findall(r'\b[A-Za-z_]\w*\b', text))

def present(name):
    return name in state_names or name in all_words

connected_var = None
for cand in ["streamConnected", "isStreamConnected", "streamOk", "streamLive", "streamOpen", "connected"]:
    if present(cand):
        connected_var = cand
        break

snapshot_terms = []

for cand in ["mid", "last", "bestBid", "bestAsk"]:
    if present(cand):
        snapshot_terms.append(f'Number.isFinite(Number({cand}))')

for cand in ["candles", "series", "ohlc", "bars"]:
    if present(cand):
        snapshot_terms.append(f'(Array.isArray({cand}) && {cand}.length > 0)')

for cand in ["trades", "tape", "items"]:
    if present(cand):
        snapshot_terms.append(f'(Array.isArray({cand}) && {cand}.length > 0)')

for cand in ["orderbook", "book"]:
    if present(cand):
        snapshot_terms.append(f'(Array.isArray({cand}?.bids) && {cand}.bids.length > 0)')
        snapshot_terms.append(f'(Array.isArray({cand}?.asks) && {cand}.asks.length > 0)')

for cand in ["openOrders", "orders", "positions", "balances"]:
    if present(cand):
        snapshot_terms.append(f'(Array.isArray({cand}) && {cand}.length > 0)')

snapshot_expr = " || ".join(snapshot_terms) if snapshot_terms else "false"
connected_expr = f"Boolean({connected_var})" if connected_var else "false"

inject = f"""
  const hasSnapshotData = {snapshot_expr};
  const connectionLabel = {connected_expr}
    ? "LIVE"
    : hasSnapshotData
      ? "SNAPSHOT"
      : "ERROR";
"""

# Insert before first "return ("
match = re.search(r'\n(\s*)return\s*\(', text)
if not match:
    print(f"Could not find return() in {target}; skipping UI patch.")
    sys.exit(0)

insert_at = match.start()
text = text[:insert_at] + "\n" + inject + text[insert_at:]

# Replace first >ERROR< or {"ERROR"} style
new_text = text
new_text, n1 = re.subn(r'>\s*ERROR\s*<', r'>{connectionLabel}<', new_text, count=1)
if n1 == 0:
    new_text, n2 = re.subn(r'\{\s*["\']ERROR["\']\s*\}', r'{connectionLabel}', new_text, count=1)
    if n2 == 0:
        print(f"Could not replace visible ERROR badge text in {target}; injected helper only.")
    else:
        print(f"Patched badge label in {target}")
else:
    print(f"Patched badge label in {target}")

target.write_text(new_text)
PY

echo
echo "==> Rebuilding locally ..."
pnpm --filter api build
pnpm --filter web build

echo
echo "✅ Stream mount + SNAPSHOT badge patch applied."
echo
echo "Next:"
echo "  docker compose build api web --no-cache"
echo "  docker compose up -d api web"
echo
echo "Then test:"
echo "  curl -N --max-time 5 \"http://127.0.0.1:4010/v1/stream/BTC-USD?mode=PAPER\""
echo "  curl -N --max-time 5 \"http://127.0.0.1:4010/v1/stream/RVAI-USD?mode=PAPER\""
echo
echo "And refresh:"
echo "  https://dcapitalx.com/markets/BTC-USD"
echo "  https://dcapitalx.com/markets/RVAI-USD"
