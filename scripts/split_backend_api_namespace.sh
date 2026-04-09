#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Backing up files..."
cp apps/api/src/app.ts "apps/api/src/app.ts.bak.$(date +%Y%m%d%H%M%S)" || true
cp apps/web/src/lib/api/client.ts "apps/web/src/lib/api/client.ts.bak.$(date +%Y%m%d%H%M%S)" || true
cp apps/web/.env.production.example "apps/web/.env.production.example.bak.$(date +%Y%m%d%H%M%S)" || true
cp apps/api/.env.production.example "apps/api/.env.production.example.bak.$(date +%Y%m%d%H%M%S)" || true

echo "==> Patching apps/api/src/app.ts to expose /backend-api ..."
python3 - <<'PY'
from pathlib import Path
p = Path("apps/api/src/app.ts")
text = p.read_text()

replacements = [
    ('app.use("/api", onboardingRoutes);', 'app.use("/api", onboardingRoutes);\napp.use("/backend-api", onboardingRoutes);'),
    ('app.use("/api", advisorRoutes);', 'app.use("/api", advisorRoutes);\napp.use("/backend-api", advisorRoutes);'),
    ('app.use("/api", uploadsRoutes);', 'app.use("/api", uploadsRoutes);\napp.use("/backend-api", uploadsRoutes);'),
    ('app.use("/api", consentsRoutes);', 'app.use("/api", consentsRoutes);\napp.use("/backend-api", consentsRoutes);'),
    ('app.use("/api", authRoutes);', 'app.use("/api", authRoutes);\napp.use("/backend-api", authRoutes);'),
    ('app.use("/api", kycRoutes);', 'app.use("/api", kycRoutes);\napp.use("/backend-api", kycRoutes);'),
    ('app.use("/api", referralsRoutes);', 'app.use("/api", referralsRoutes);\napp.use("/backend-api", referralsRoutes);'),
]

for old, new in replacements:
    if old in text and new not in text:
        text = text.replace(old, new)

p.write_text(text)
PY

echo "==> Rewriting apps/web/src/lib/api/client.ts ..."
cat > apps/web/src/lib/api/client.ts <<'EOF'
const API_BASE =
  process.env.NEXT_PUBLIC_API_BASE_URL?.replace(/\/$/, "") || "";

function resolveUrl(input: string): string {
  if (input.startsWith("http")) return input;

  if (!API_BASE) return input;

  if (input.startsWith("/api/")) {
    return `${API_BASE}${input.slice(4)}`;
  }

  return `${API_BASE}${input}`;
}

export async function apiFetch<T>(input: string, init?: RequestInit): Promise<T> {
  const url = resolveUrl(input);

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

echo "==> Writing apps/web/.env.production.example ..."
cat > apps/web/.env.production.example <<'EOF'
NEXT_PUBLIC_API_BASE_URL=/backend-api
API_INTERNAL_URL=http://api:4010
EOF

echo "==> Writing apps/api/.env.production.example ..."
cat > apps/api/.env.production.example <<'EOF'
DATABASE_URL=postgresql://USER:PASSWORD@HOST:5432/DCAPX
JWT_SECRET=CHANGE_ME
APP_BASE_URL=https://dcapitalx.com
NODE_ENV=production
PORT=4010
EOF

echo
echo "✅ Namespace split patch written."
echo
echo "Next steps:"
echo "  1) pnpm --filter api build"
echo "  2) pnpm --filter web build"
echo "  3) rebuild both containers"
echo "  4) update nginx so /backend-api goes to Express and / goes to Next"
