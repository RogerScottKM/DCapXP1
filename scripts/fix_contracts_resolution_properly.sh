#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Backing up key files..."
cp packages/contracts/package.json "packages/contracts/package.json.bak.$(date +%Y%m%d%H%M%S)" || true
cp packages/contracts/tsconfig.json "packages/contracts/tsconfig.json.bak.$(date +%Y%m%d%H%M%S)" || true
cp apps/api/tsconfig.json "apps/api/tsconfig.json.bak.$(date +%Y%m%d%H%M%S)" || true
cp apps/web/tsconfig.json "apps/web/tsconfig.json.bak.$(date +%Y%m%d%H%M%S)" || true
cp apps/api/Dockerfile "apps/api/Dockerfile.bak.$(date +%Y%m%d%H%M%S)" || true

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
    "declarationMap": false,
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

echo "==> Removing @dcapx/contracts tsconfig path aliases from api/web/root tsconfigs ..."
node <<'NODE'
const fs = require("fs");
const paths = [
  "tsconfig.json",
  "apps/api/tsconfig.json",
  "apps/web/tsconfig.json"
];

for (const path of paths) {
  if (!fs.existsSync(path)) continue;
  const raw = fs.readFileSync(path, "utf8");
  let json;
  try {
    json = JSON.parse(raw);
  } catch (e) {
    console.error(`Could not parse ${path} as JSON. Please fix manually.`);
    process.exit(1);
  }

  json.compilerOptions = json.compilerOptions || {};
  const p = json.compilerOptions.paths || {};

  delete p["@dcapx/contracts"];
  delete p["@dcapx/contracts/*"];

  if (Object.keys(p).length === 0) {
    delete json.compilerOptions.paths;
  } else {
    json.compilerOptions.paths = p;
  }

  if (path === "apps/api/tsconfig.json") {
    json.compilerOptions.rootDir = "src";
    json.compilerOptions.outDir = "dist";
    json.compilerOptions.noEmit = false;
  }

  fs.writeFileSync(path, JSON.stringify(json, null, 2) + "\n");
}
NODE

echo "==> Ensuring api/web depend on @dcapx/contracts ..."
node <<'NODE'
const fs = require("fs");

for (const path of ["apps/api/package.json", "apps/web/package.json"]) {
  const pkg = JSON.parse(fs.readFileSync(path, "utf8"));
  pkg.dependencies = pkg.dependencies || {};
  pkg.dependencies["@dcapx/contracts"] = "workspace:*";
  fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + "\n");
}
NODE

echo "==> Rewriting apps/api/Dockerfile so contracts build before api ..."
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

echo "==> Cleaning local build artifacts ..."
rm -rf apps/api/dist
rm -rf apps/web/.next
rm -rf packages/contracts/dist

echo
echo "==> Installing workspace deps ..."
pnpm install

echo
echo "==> Building contracts first ..."
pnpm --filter @dcapx/contracts build

echo
echo "==> Building api ..."
pnpm --filter api build

echo
echo "==> Building web ..."
pnpm --filter web build

echo
echo "✅ Contracts resolution fix applied."
echo
echo "Next:"
echo "  docker compose build api --no-cache"
echo "  docker compose up -d api"
echo "  docker compose logs api --tail=120"
echo "  curl http://127.0.0.1:4010/health"
