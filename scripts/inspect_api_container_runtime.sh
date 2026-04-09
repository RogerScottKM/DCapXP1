#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> docker compose ps"
docker compose ps || true

echo
echo "==> last 200 api logs"
docker compose logs api --tail=200 || true

echo
echo "==> inspect running container workdir + dist"
docker compose exec api sh -lc '
  echo "--- pwd ---"
  pwd
  echo
  echo "--- ls -la ---"
  ls -la
  echo
  echo "--- ls -la dist ---"
  ls -la dist || true
  echo
  echo "--- dist/server.js ---"
  sed -n "1,60p" dist/server.js || true
  echo
  echo "--- dist/app.js ---"
  sed -n "1,80p" dist/app.js || true
  echo
  echo "--- env ---"
  printenv | grep -E "PORT|API_PORT|NODE_ENV|DATABASE_URL|APP_BASE_URL" || true
  echo
  echo "--- curl localhost health inside container ---"
  curl -i http://127.0.0.1:4010/health || true
' || true

echo
echo "==> restart count / health"
docker inspect --format '{{json .State}}' dcapx-api-1 || true
