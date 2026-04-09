#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

LAYOUT="apps/web/app/layout.tsx"
PROVIDERS="apps/web/app/Providers.tsx"

if [ ! -f "$LAYOUT" ]; then
  echo "Missing $LAYOUT"
  exit 1
fi

backup "$LAYOUT"
mkdir -p apps/web/app

echo "==> Writing App Router Providers wrapper ..."
cat > "$PROVIDERS" <<'EOF'
"use client";

import type { ReactNode } from "react";
import { PortalPreferencesProvider } from "../src/lib/preferences/PortalPreferencesProvider";

export default function Providers({ children }: { children: ReactNode }) {
  return <PortalPreferencesProvider>{children}</PortalPreferencesProvider>;
}
EOF

echo "==> Patching app/layout.tsx ..."
python3 - <<'PY'
from pathlib import Path
import re
import sys

path = Path("apps/web/app/layout.tsx")
text = path.read_text()

if 'import Providers from "./Providers";' not in text:
    lines = text.splitlines()
    insert_at = 0
    for i, line in enumerate(lines):
        if line.startswith("import "):
            insert_at = i + 1
    lines.insert(insert_at, 'import Providers from "./Providers";')
    text = "\n".join(lines) + ("\n" if text.endswith("\n") else "")

# Wrap body contents if not already wrapped
if "<Providers>" not in text:
    body_pattern = re.compile(r'(<body\b[^>]*>)([\s\S]*?)(</body>)', re.MULTILINE)
    m = body_pattern.search(text)
    if not m:
        print("Could not find <body>...</body> in apps/web/app/layout.tsx")
        sys.exit(1)

    open_tag, inner, close_tag = m.groups()
    replacement = f'{open_tag}\n      <Providers>{inner}</Providers>\n    {close_tag}'
    text = text[:m.start()] + replacement + text[m.end():]

path.write_text(text)
print("Patched apps/web/app/layout.tsx")
PY

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ App Router PortalPreferencesProvider patch applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
echo "  docker compose logs web --tail=80"
