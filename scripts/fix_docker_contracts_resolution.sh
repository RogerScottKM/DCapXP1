#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p scripts
mkdir -p packages/contracts
mkdir -p apps/api
mkdir -p apps/web

echo "==> Patching workspace package metadata..."

node <<'NODE'
const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function writeJson(path, obj) {
  fs.writeFileSync(path, JSON.stringify(obj, null, 2) + "\n");
}

function ensureDep(pkgPath, depName) {
  const pkg = readJson(pkgPath);
  pkg.dependencies = pkg.dependencies || {};
  if (!pkg.dependencies[depName]) {
    pkg.dependencies[depName] = "workspace:*";
  }
  writeJson(pkgPath, pkg);
}

const contractsPkgPath = "packages/contracts/package.json";
let contractsPkg = {};
if (fs.existsSync(contractsPkgPath)) {
  contractsPkg = readJson(contractsPkgPath);
}

contractsPkg.name = "@dcapx/contracts";
contractsPkg.version = contractsPkg.version || "0.0.0";
contractsPkg.private = true;
contractsPkg.main = "dist/index.js";
contractsPkg.types = "dist/index.d.ts";
contractsPkg.files = ["dist"];
contractsPkg.scripts = contractsPkg.scripts || {};
contractsPkg.scripts.build = "tsc -p tsconfig.json";

contractsPkg.devDependencies = contractsPkg.devDependencies || {};
if (!contractsPkg.devDependencies.typescript) {
  contractsPkg.devDependencies.typescript = "^5.9.3";
}

writeJson(contractsPkgPath, contractsPkg);

ensureDep("apps/api/package.json", "@dcapx/contracts");
ensureDep("apps/web/package.json", "@dcapx/contracts");
NODE

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

echo "==> Writing apps/api/Dockerfile ..."

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

CMD ["pnpm", "start"]
EOF

echo "==> Writing apps/web/Dockerfile ..."

cat > apps/web/Dockerfile <<'EOF'
FROM node:18-bookworm-slim AS builder

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@10.20.0 --activate

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/web/package.json apps/web/package.json
COPY packages/schema/package.json packages/schema/package.json
COPY packages/contracts/package.json packages/contracts/package.json

RUN pnpm install --frozen-lockfile

COPY apps/web apps/web
COPY packages/schema packages/schema
COPY packages/contracts packages/contracts

RUN pnpm --filter @dcapx/contracts build
RUN pnpm --filter @repo/schema build
RUN pnpm --filter web build

FROM node:18-bookworm-slim AS runner

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@10.20.0 --activate

ENV NODE_ENV=production

COPY --from=builder /app/package.json /app/pnpm-lock.yaml /app/pnpm-workspace.yaml ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/apps/web ./apps/web
COPY --from=builder /app/packages/schema ./packages/schema
COPY --from=builder /app/packages/contracts ./packages/contracts

WORKDIR /app/apps/web
EXPOSE 3000

CMD ["pnpm", "start"]
EOF

echo
echo "✅ Docker contracts resolution pack written."
echo
echo "Next:"
echo "  1) check docker-compose.yml points to apps/api/Dockerfile and apps/web/Dockerfile"
echo "  2) pnpm --filter @dcapx/contracts build"
echo "  3) pnpm --filter api build"
echo "  4) pnpm --filter web build"
echo "  5) docker compose build --no-cache"
