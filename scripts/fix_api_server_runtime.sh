#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p apps/api/src

if [ -f apps/api/src/server.ts ]; then
  cp apps/api/src/server.ts "apps/api/src/server.ts.bak.$(date +%Y%m%d%H%M%S)"
fi

cat > apps/api/src/server.ts <<'EOF'
import "dotenv/config";
import { startBotFarm } from "./botFarm";
import app from "./app";

const PORT = Number(process.env.API_PORT ?? process.env.PORT ?? 4010);

app.listen(PORT, () => {
  console.log(`api listening on ${PORT}`);

  if (process.env.ENABLE_BOT_FARM === "1") {
    startBotFarm().catch((e) => console.error("[botFarm]", e));
  }
});

process.on("unhandledRejection", (e) => console.error("unhandledRejection", e));
process.on("uncaughtException", (e) => console.error("uncaughtException", e));
EOF

echo
echo "✅ apps/api/src/server.ts rewritten to use default app export."
echo "Next:"
echo "  pnpm --filter api build"
echo "  docker compose build api --no-cache"
echo "  docker compose up -d api"
