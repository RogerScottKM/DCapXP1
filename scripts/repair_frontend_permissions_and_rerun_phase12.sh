#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

TARGET_FILE="apps/web/src/features/auth/ResetPasswordPage.tsx"
TARGET_DIRS=(
  "apps/web/src/features/auth"
  "apps/web/src/features/onboarding"
  "apps/web/src/lib/api"
  "apps/web/pages"
  "apps/web/pages/app"
)

echo "==> Inspecting current path state ..."
ls -ld apps/web/src/features/auth || true
ls -ld "$TARGET_FILE" || true
namei -l "$TARGET_FILE" || true

echo
echo "==> Ensuring directories exist ..."
for d in "${TARGET_DIRS[@]}"; do
  sudo mkdir -p "$d"
done

echo
echo "==> Fixing ownership ..."
sudo chown -R "$USER":"$(id -gn)" \
  apps/web/src/features/auth \
  apps/web/src/features/onboarding \
  apps/web/src/lib/api \
  apps/web/pages

echo
echo "==> Fixing permissions ..."
chmod -R u+rwX \
  apps/web/src/features/auth \
  apps/web/src/features/onboarding \
  apps/web/src/lib/api \
  apps/web/pages

echo
echo "==> If ResetPasswordPage.tsx is accidentally a directory, move it aside ..."
if [ -d "$TARGET_FILE" ]; then
  mv "$TARGET_FILE" "${TARGET_FILE}.bad_dir.$(date +%Y%m%d%H%M%S)"
fi

echo
echo "==> Re-checking path state ..."
ls -ld apps/web/src/features/auth || true
ls -ld "$TARGET_FILE" || true
namei -l "$TARGET_FILE" || true

echo
echo "==> Re-running the frontend pack ..."
bash scripts/phase12_frontend_email_verification_and_reset.sh

echo
echo "==> Rebuilding web container ..."
docker compose build web --no-cache
docker compose up -d web

echo
echo "✅ Frontend permission repair complete."
