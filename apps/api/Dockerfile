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
