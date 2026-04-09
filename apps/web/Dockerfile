FROM node:18-bookworm-slim AS builder

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@10.20.0 --activate

ARG NEXT_PUBLIC_API_BASE_URL=/backend-api
ARG API_INTERNAL_URL=http://api:4010

ENV NEXT_PUBLIC_API_BASE_URL=${NEXT_PUBLIC_API_BASE_URL}
ENV API_INTERNAL_URL=${API_INTERNAL_URL}

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/web/package.json apps/web/package.json
COPY packages/schema/package.json packages/schema/package.json
COPY packages/contracts/package.json packages/contracts/package.json

RUN pnpm install --frozen-lockfile

COPY apps/web apps/web
COPY packages/schema packages/schema
COPY packages/contracts packages/contracts

RUN pnpm --filter @dcapx/contracts build
RUN pnpm --filter @repo/schema build || true
RUN pnpm --filter web build

FROM node:18-bookworm-slim AS runner

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@10.20.0 --activate

ARG NEXT_PUBLIC_API_BASE_URL=/backend-api
ARG API_INTERNAL_URL=http://api:4010

ENV NODE_ENV=production
ENV NEXT_PUBLIC_API_BASE_URL=${NEXT_PUBLIC_API_BASE_URL}
ENV API_INTERNAL_URL=${API_INTERNAL_URL}

COPY --from=builder /app/package.json /app/pnpm-lock.yaml /app/pnpm-workspace.yaml ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/apps/web ./apps/web
COPY --from=builder /app/packages/schema ./packages/schema
COPY --from=builder /app/packages/contracts ./packages/contracts

WORKDIR /app/apps/web
EXPOSE 3000

CMD ["pnpm", "start"]
