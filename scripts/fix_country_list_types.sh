#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

FILE="apps/web/src/lib/countries.ts"

if [ -f "$FILE" ]; then
  cp "$FILE" "${FILE}.bak.$(date +%Y%m%d%H%M%S)"
fi

cat > "$FILE" <<'EOF'
type CountryListItem = {
  code: string;
  name: string;
};

type CountryListModule = {
  getData: () => CountryListItem[];
};

const { getData } = require("country-list") as CountryListModule;

export type CountryOption = {
  code: string;
  name: string;
};

export const COUNTRY_OPTIONS: CountryOption[] = getData()
  .map((item) => ({
    code: item.code.toUpperCase(),
    name: item.name,
  }))
  .sort((a, b) => a.name.localeCompare(b.name));

export function getCountryName(code: string): string {
  const normalized = code.trim().toUpperCase();
  return COUNTRY_OPTIONS.find((item) => item.code === normalized)?.name ?? normalized;
}
EOF

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ country-list typing issue fixed."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
