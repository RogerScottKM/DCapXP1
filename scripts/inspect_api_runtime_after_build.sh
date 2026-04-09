#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> docker compose ps"
docker compose ps || true

echo
echo "==> api logs"
docker compose logs api --tail=200 || true

echo
echo "==> api health"
docker inspect --format '{{json .State.Health}}' dcapx-api-1 || true

echo
echo "==> api full state"
docker inspect --format '{{json .State}}' dcapx-api-1 || true

echo
echo "==> api env"
docker compose exec api sh -lc 'printenv | grep -E "PORT|API_PORT|NODE_ENV|ENABLE_BOT_FARM|DATABASE_URL"' || true
