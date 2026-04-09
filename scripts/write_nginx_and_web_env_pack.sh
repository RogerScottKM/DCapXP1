#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p deploy/nginx
mkdir -p scripts

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

echo "==> Backing up files..."
backup apps/web/Dockerfile
backup docker-compose.override.yml

echo "==> Writing apps/web/Dockerfile ..."
cat > apps/web/Dockerfile <<'EOF'
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
EOF

echo "==> Writing docker-compose.override.yml ..."
cat > docker-compose.override.yml <<'EOF'
services:
  api:
    environment:
      PORT: 4010

  web:
    build:
      args:
        NEXT_PUBLIC_API_BASE_URL: /backend-api
        API_INTERNAL_URL: http://api:4010
    environment:
      NEXT_PUBLIC_API_BASE_URL: /backend-api
      API_INTERNAL_URL: http://api:4010
EOF

echo "==> Writing nginx locations snippet ..."
cat > deploy/nginx/dcapitalx.portal.locations.conf <<'EOF'
# Paste these location blocks inside your active server block for:
# server_name dcapitalx.com www.dcapitalx.com;

location /backend-api/ {
    proxy_pass http://127.0.0.1:4010/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}

location /api/ {
    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}

location = /onboarding {
    return 302 /app/onboarding;
}

location = /kyc {
    return 302 /app/kyc;
}

location = /consents {
    return 302 /app/consents;
}

location = /verify-contact {
    return 302 /app/verify-contact;
}

location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
EOF

echo "==> Writing full nginx example ..."
cat > deploy/nginx/dcapitalx.portal.server.conf.example <<'EOF'
server {
    listen 80;
    server_name dcapitalx.com www.dcapitalx.com;

    location /backend-api/ {
        proxy_pass http://127.0.0.1:4010/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /api/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location = /onboarding {
        return 302 /app/onboarding;
    }

    location = /kyc {
        return 302 /app/kyc;
    }

    location = /consents {
        return 302 /app/consents;
    }

    location = /verify-contact {
        return 302 /app/verify-contact;
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

echo "==> Writing install notes ..."
cat > deploy/nginx/INSTALL_DCAPITALX_PORTAL.txt <<'EOF'
1) Rebuild and restart web + api:
   docker compose build web api --no-cache
   docker compose up -d web api

2) Find your live nginx site file, commonly one of:
   /etc/nginx/sites-available/dcapitalx.com
   /etc/nginx/sites-available/default

3) Paste the contents of:
   deploy/nginx/dcapitalx.portal.locations.conf

   inside the active server block for:
   server_name dcapitalx.com www.dcapitalx.com;

4) Test nginx:
   sudo nginx -t

5) Reload nginx:
   sudo systemctl reload nginx

6) Test:
   curl -i http://127.0.0.1:4010/health
   curl -i https://dcapitalx.com/backend-api/health
   curl -I https://dcapitalx.com/onboarding
   curl -I https://dcapitalx.com/kyc

7) Browser checks:
   https://dcapitalx.com/login
   https://dcapitalx.com/app/onboarding
   https://dcapitalx.com/app/kyc
   https://dcapitalx.com/markets/BTC-USD
   https://dcapitalx.com/markets/RVAI-USD
EOF

echo
echo "✅ Nginx + web env pack written."
echo
echo "Files created:"
echo "  apps/web/Dockerfile"
echo "  docker-compose.override.yml"
echo "  deploy/nginx/dcapitalx.portal.locations.conf"
echo "  deploy/nginx/dcapitalx.portal.server.conf.example"
echo "  deploy/nginx/INSTALL_DCAPITALX_PORTAL.txt"
echo
echo "Next:"
echo "  docker compose build web api --no-cache"
echo "  docker compose up -d web api"
echo
echo "Then paste deploy/nginx/dcapitalx.portal.locations.conf into your live nginx server block."
echo "Then run:"
echo "  sudo nginx -t"
echo "  sudo systemctl reload nginx"
