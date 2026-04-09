#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

backup apps/api/src/app.ts

python3 - <<'PY'
from pathlib import Path

p = Path("apps/api/src/app.ts")
text = p.read_text()

needle = 'const app = express();'
insert = '''const app = express();

// Global JSON replacer so Express can safely serialize Prisma BigInt values
app.set("json replacer", (_key: string, value: unknown) => {
  return typeof value === "bigint" ? value.toString() : value;
});
'''

if needle in text and 'app.set("json replacer"' not in text:
    text = text.replace(needle, insert)

p.write_text(text)
PY

echo "==> Rebuilding API..."
pnpm --filter api build

echo
echo "✅ BigInt JSON serialization patch applied."
echo
echo "Next run:"
echo "  docker compose build api --no-cache"
echo "  docker compose up -d api"
echo "  docker compose logs api --tail=120"
echo "  curl -i \"http://127.0.0.1:4010/v1/market/trades?symbol=BTC-USD&limit=20&mode=PAPER\""
echo "  curl -i \"http://127.0.0.1:4010/v1/market/trades?symbol=RVAI-USD&limit=20&mode=PAPER\""
