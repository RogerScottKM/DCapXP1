# apps/web/Dockerfile

########################
# 1) Builder
########################
FROM node:18-bookworm-slim AS builder
WORKDIR /app

RUN corepack enable && corepack prepare pnpm@10.20.0 --activate

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/web/package.json apps/web/package.json
COPY packages/schema/package.json packages/schema/package.json

RUN pnpm install --frozen-lockfile

COPY packages/schema packages/schema
COPY apps/web apps/web

RUN pnpm --filter @repo/schema build
RUN pnpm --filter web build

########################
# 2) Runner
########################
########################
# 2) Runner
########################
FROM node:18-bookworm-slim AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

# Standalone output
COPY --from=builder /app/apps/web/.next/standalone /app

# ✅ Put static where server.js (in /app/apps/web) expects it
COPY --from=builder /app/apps/web/.next/static /app/apps/web/.next/static

# ✅ Also keep root copy (harmless, helps if Next expects root)
COPY --from=builder /app/apps/web/.next/static /app/.next/static

# ✅ Public where server.js expects it
COPY --from=builder /app/apps/web/public /app/apps/web/public

# ✅ Also keep root public
COPY --from=builder /app/apps/web/public /app/public

EXPOSE 3000
CMD ["node", "/app/apps/web/server.js"]
