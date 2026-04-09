#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

mkdir -p apps/web/src/lib/theme

backup apps/web/src/lib/theme/usePortalTheme.ts

echo "==> Rewriting legacy usePortalTheme.ts as a no-JSX shim ..."
cat > apps/web/src/lib/theme/usePortalTheme.ts <<'EOF'
import {
  usePortalPreferences,
  type PortalTheme,
  PortalPreferencesProvider,
} from "../preferences/PortalPreferencesProvider";

export type { PortalTheme };

export { PortalPreferencesProvider as PortalThemeProvider };

export function usePortalTheme() {
  const {
    theme,
    isDark,
    isLight,
    mounted,
    setTheme,
    toggleTheme,
  } = usePortalPreferences();

  return {
    theme,
    isDark,
    isLight,
    mounted,
    setTheme,
    toggleTheme,
  };
}
EOF

echo
echo "==> Showing remaining theme imports ..."
rg -n "usePortalTheme|PortalThemeProvider" apps/web || true

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ Legacy theme shim fixed."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
