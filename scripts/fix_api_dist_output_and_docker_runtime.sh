#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Backing up files..."
cp apps/api/tsconfig.json "apps/api/tsconfig.json.bak.$(date +%Y%m%d%H%M%S)" || true
cp apps/api/package.json "apps/api/package.json.bak.$(date +%Y%m%d%H%M%S)" || true
cp apps/api/Dockerfile "apps/api/Dockerfile.bak.$(date +%Y%m%d%H%M%S)" || true
cp docker-compose.yml "docker-compose.yml.bak.$(date +%Y%m%d%H%M%S)" || true

echo "==> Patching apps/api/tsconfig.json ..."
node <<'NODE'
const fs = require("fs");
const path = "apps/api/tsconfig.json";
const raw = fs.readFileSync(path, "utf8");
const json = JSON.parse(raw);

json.compilerOptions = json.compilerOptions || {};
json.compilerOptions.rootDir = "src";
json.compilerOptions.outDir = "dist";
json.compilerOptions.noEmit = false;

fs.writeFileSync(path, JSON.stringify(json, null, 2) + "\n");
NODE

echo "==> Patching apps/api/package.json ..."
node <<'NODE'
const fs = require("fs");
const path = "apps/api/package.json";
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));

pkg.scripts = pkg.scripts || {};
pkg.scripts.build = "tsc -p tsconfig.json";
pkg.scripts.start = "node dist/server.js";

fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + "\n");
NODE

echo "==> Rewriting apps/api/Dockerfile ..."
cat > apps/api/Dockerfile <<'EOF'
FROM node:18-bookworm-slim

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@10.20.0 --activate \
  && apt-get update -y \
  && apt-get install -y --no-install-recommends curl openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/api/package.json apps/api/package.json
COPY apps/web/package.json apps/web/package.json
COPY packages/schema/package.json packages/schema/package.json
COPY packages/contracts/package.json packages/contracts/package.json

RUN pnpm install --frozen-lockfile

COPY apps/api apps/api
COPY packages/schema packages/schema
COPY packages/contracts packages/contracts

RUN pnpm --filter @dcapx/contracts build
RUN pnpm --filter api exec prisma generate
RUN rm -rf apps/api/dist && pnpm --filter api build
RUN test -f /app/apps/api/dist/server.js

WORKDIR /app/apps/api
ENV NODE_ENV=production
EXPOSE 4010

CMD ["sh", "-lc", "pnpm prisma migrate deploy && pnpm start"]
EOF

echo "==> Patching docker-compose.yml API command/health assumptions ..."
python3 <<'PY'
from pathlib import Path
p = Path("docker-compose.yml")
text = p.read_text()

text = text.replace(
    'pnpm prisma:generate && pnpm prisma:migrate:deploy && node dist/server.js',
    'pnpm prisma migrate deploy && pnpm start'
)
text = text.replace(
    'pnpm prisma generate && pnpm prisma migrate deploy && node dist/server.js',
    'pnpm prisma migrate deploy && pnpm start'
)
text = text.replace(
    'pnpm prisma:generate && pnpm prisma:migrate:deploy && pnpm start',
    'pnpm prisma migrate deploy && pnpm start'
)

p.write_text(text)
PY

echo "==> Cleaning local build artifacts ..."
rm -rf apps/api/dist
rm -rf apps/web/.next

echo
echo "==> Verifying local API build now emits dist/server.js ..."
pnpm --filter api build
test -f apps/api/dist/server.js

echo
echo "✅ API dist output + Docker runtime pack applied."
echo
echo "Next run:"
echo "  docker compose build api --no-cache"
echo "  docker compose up -d api"
echo "  docker compose logs api --tail=120"
echo "  curl http://127.0.0.1:4010/health"
