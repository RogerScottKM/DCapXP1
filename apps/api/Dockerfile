FROM node:18-bookworm-slim

WORKDIR /app

# pnpm
RUN corepack enable && corepack prepare pnpm@10.20.0 --activate

# Copy workspace manifests first (better caching)
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/api/package.json apps/api/package.json
COPY apps/web/package.json apps/web/package.json
COPY packages/schema/package.json packages/schema/package.json

# Install ... curl

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends curl openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Install deps (includes prisma CLI from devDependencies)
RUN pnpm install --frozen-lockfile

# Copy API source
COPY apps/api apps/api
COPY packages/schema packages/schema

# Build API + generate prisma client
RUN pnpm --filter api exec prisma generate
RUN pnpm --filter api build

WORKDIR /app/apps/api
ENV NODE_ENV=production

EXPOSE 4010

# Run migrations on container start, then start server
CMD ["bash","-lc","pnpm prisma migrate deploy && node dist/server.js"]
