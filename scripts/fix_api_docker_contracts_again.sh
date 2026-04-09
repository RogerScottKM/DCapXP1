#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

echo "==> Backing up files..."
backup apps/api/Dockerfile
backup apps/api/package.json
backup packages/contracts/package.json
backup packages/contracts/tsconfig.json

mkdir -p packages/contracts

echo "==> Writing packages/contracts/package.json ..."
cat > packages/contracts/package.json <<'EOF'
{
  "name": "@dcapx/contracts",
  "version": "1.0.0-phase1",
  "private": true,
  "type": "commonjs",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "files": ["dist"],
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "default": "./dist/index.js"
    }
  },
  "scripts": {
    "build": "tsc -p tsconfig.json"
  },
  "devDependencies": {
    "typescript": "^5.9.3"
  }
}
EOF

echo "==> Writing packages/contracts/tsconfig.json ..."
cat > packages/contracts/tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "CommonJS",
    "moduleResolution": "Node",
    "declaration": true,
    "emitDeclarationOnly": false,
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*.ts"]
}
EOF

echo "==> Ensuring apps/api depends on @dcapx/contracts ..."
node <<'NODE'
const fs = require("fs");
const path = "apps/api/package.json";
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));
pkg.dependencies = pkg.dependencies || {};
pkg.dependencies["@dcapx/contracts"] = "workspace:*";
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
RUN pnpm --filter api build

WORKDIR /app/apps/api
ENV NODE_ENV=production
EXPOSE 4010

CMD ["sh", "-lc", "pnpm prisma migrate deploy && pnpm start"]
EOF

echo
echo "==> Installing workspace deps locally ..."
pnpm install

echo
echo "==> Verifying local contracts build ..."
pnpm --filter @dcapx/contracts build

echo
echo "==> Verifying local api build ..."
pnpm --filter api build

echo
echo "✅ API Docker contracts patch applied."
echo
echo "Next:"
echo "  docker compose build api --no-cache"
echo "  docker compose up -d api"
echo "  docker compose logs api --tail=120"
echo "  curl -i http://127.0.0.1:4010/health"
