#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p apps/web/src/lib/api
mkdir -p deploy/nginx
mkdir -p docs

cat > apps/web/src/lib/api/client.ts <<'EOF'
const API_BASE =
  process.env.NEXT_PUBLIC_API_BASE_URL?.replace(/\/$/, "") || "";

export async function apiFetch<T>(input: string, init?: RequestInit): Promise<T> {
  const url = input.startsWith("http") ? input : `${API_BASE}${input}`;

  const response = await fetch(url, {
    credentials: "include",
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers || {}),
    },
    ...init,
  });

  let parsed: any = null;

  try {
    parsed = await response.json();
  } catch {
    parsed = null;
  }

  if (!response.ok) {
    throw (
      parsed || {
        error: {
          code: "HTTP_ERROR",
          message: `Request failed with status ${response.status}.`,
        },
      }
    );
  }

  return parsed as T;
}
EOF

cat > apps/web/.env.production.example <<'EOF'
NEXT_PUBLIC_API_BASE_URL=
EOF

cat > apps/api/.env.production.example <<'EOF'
DATABASE_URL=postgresql://USER:PASSWORD@HOST:5432/DCAPX
JWT_SECRET=CHANGE_ME
APP_BASE_URL=https://dcapitalx.com
NODE_ENV=production
PORT=4010
API_INTERNAL_URL=http://127.0.0.1:4010
EOF

cat > deploy/nginx/dcapitalx.portal.conf.example <<'EOF'
server {
    listen 443 ssl http2;
    server_name dcapitalx.com www.dcapitalx.com;

    # SSL directives omitted here for brevity
    # ssl_certificate ...
    # ssl_certificate_key ...

    location /api/ {
        proxy_pass http://127.0.0.1:4010;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
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

cat > docs/PORTAL_MERGE_CHECKLIST.md <<'EOF'
# Portal Merge Checklist

## Goal
Serve the DCapX public site and authenticated portal from one domain:

- `/` -> Next.js
- `/api/*` -> Express API

## Required routes to verify
- `/login`
- `/register`
- `/forgot-password`
- `/reset-password`
- `/app/onboarding`
- `/app/verify-contact`
- `/app/consents`
- `/app/kyc`

## Browser API calls
Use same-origin in production:
- `NEXT_PUBLIC_API_BASE_URL=` (empty)

## Internal server-side API calls
Use:
- `API_INTERNAL_URL=http://127.0.0.1:4010`

## Build commands
```bash
pnpm --filter api build
pnpm --filter web build
EOF
