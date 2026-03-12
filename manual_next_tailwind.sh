set -euo pipefail

BASE="$HOME/dcapx"
WEB="$BASE/apps/web"
API="$BASE/apps/api"

mkdir -p "$BASE" "$WEB" "$API"

# root workspace
cat > "$BASE/pnpm-workspace.yaml" <<'YML'
packages:
  - "apps/*"
  - "packages/*"
YML

cat > "$BASE/package.json" <<'JSON'
{
  "name": "dcapx",
  "private": true,
  "packageManager": "pnpm@10.20.0",
  "workspaces": ["apps/*","packages/*"],
  "scripts": {
    "dev:web": "pnpm --filter web dev",
    "dev:api": "pnpm --filter api dev",
    "dev": "concurrently -n web,api -c green,cyan \"pnpm dev:web\" \"pnpm dev:api\""
  },
  "devDependencies": {
    "concurrently": "^9.2.1"
  }
}
JSON

# --- Web (Next 14 + Tailwind) ---
mkdir -p "$WEB"
cat > "$WEB/package.json" <<'JSON'
{
  "name": "web",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "next dev -p 3000",
    "build": "next build",
    "start": "next start -p 3000"
  },
  "dependencies": {
    "next": "14.2.5",
    "react": "18.3.1",
    "react-dom": "18.3.1"
  },
  "devDependencies": {
    "@types/node": "^20.14.10",
    "@types/react": "^18.3.5",
    "@types/react-dom": "^18.3.0",
    "autoprefixer": "^10.4.20",
    "postcss": "^8.4.47",
    "tailwindcss": "^3.4.10",
    "typescript": "^5.6.3"
  }
}
JSON

cat > "$WEB/tsconfig.json" <<'JSON'
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["dom", "dom.iterable", "es2020"],
    "allowJs": false,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "types": ["node", "react", "react-dom"]
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx"],
  "exclude": ["node_modules"]
}
JSON

cat > "$WEB/next.config.mjs" <<'JS'
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  experimental: { appDir: true }
}
export default nextConfig;
JS

cat > "$WEB/postcss.config.js" <<'JS'
module.exports = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
};
JS

cat > "$WEB/tailwind.config.ts" <<'TS'
import type { Config } from "tailwindcss";
const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: { extend: {} },
  plugins: [],
};
export default config;
TS

mkdir -p "$WEB/app" "$WEB/components" "$WEB/public" "$WEB/styles"
cat > "$WEB/styles/globals.css" <<'CSS'
@tailwind base;
@tailwind components;
@tailwind utilities;

:root { color-scheme: light dark; }
body { @apply bg-slate-950 text-slate-100; }
CSS

cat > "$WEB/app/layout.tsx" <<'TSX'
import "./../styles/globals.css";
import type { ReactNode } from "react";

export const metadata = {
  title: "DCapX",
  description: "Agent-native digital exchange"
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
TSX

# Simple home page
cat > "$WEB/app/page.tsx" <<'TSX'
export default function Home() {
  return (
    <main className="min-h-dvh grid place-items-center p-8">
      <div className="max-w-3xl w-full space-y-6">
        <h1 className="text-3xl font-bold">DCapX — Agent-Native Exchange</h1>
        <p className="text-slate-300">
          This is a minimal Next.js + Tailwind scaffold (manual). Web runs on port 3000, API on 4010.
        </p>
        <div className="rounded-xl border border-slate-800 p-4">
          <p className="text-sm">API health: <code className="text-emerald-300">GET /health</code> on port 4010</p>
        </div>
      </div>
    </main>
  );
}
TSX

# --- API (Express TS) ---
mkdir -p "$API/src"
cat > "$API/package.json" <<'JSON'
{
  "name": "api",
  "type": "module",
  "scripts": {
    "dev": "tsx watch src/server.ts",
    "build": "tsc -p tsconfig.json",
    "start": "node dist/server.js"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "express": "^4.21.1"
  },
  "devDependencies": {
    "tsx": "^4.19.0",
    "typescript": "^5.6.3"
  }
}
JSON

cat > "$API/tsconfig.json" <<'JSON'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "esModuleInterop": true,
    "strict": true,
    "skipLibCheck": true,
    "outDir": "dist",
    "types": ["node"]
  },
  "include": ["src/**/*"]
}
JSON

cat > "$API/src/server.ts" <<'TS'
import express from "express";
import cors from "cors";

const app = express();
app.use(cors());
app.get("/", (_req, res) => res.json({ ok: true, service: "dcapx-api" }));
app.get("/health", (_req, res) => res.json({ ok: true, ts: new Date().toISOString() }));

const PORT = Number(process.env.PORT || "4010");
app.listen(PORT, () => console.log(`api listening on :${PORT}`));
TS

# install all
cd "$BASE"
pnpm install
