#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

find_page() {
  local name="$1"
  find apps/web/src -type f -name "$name" | head -n 1
}

to_import_path() {
  python3 - "$1" "$2" <<'PY'
from pathlib import Path
import sys

from_file = Path(sys.argv[1])
target = Path(sys.argv[2])

rel = Path(
    Path(
        __import__("os").path.relpath(target, from_file.parent)
    ).as_posix()
)

s = rel.as_posix()
if s.endswith(".tsx"):
    s = s[:-4]
elif s.endswith(".ts"):
    s = s[:-3]

if not s.startswith("."):
    s = "./" + s

print(s)
PY
}

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

ONBOARDING_FILE="$(find_page OnboardingPage.tsx || true)"
VERIFY_FILE="$(find_page VerifyContactPage.tsx || true)"
CONSENTS_FILE="$(find_page ConsentsPage.tsx || true)"
KYC_FILE="$(find_page KycPage.tsx || true)"

echo "Detected:"
echo "  OnboardingPage:   ${ONBOARDING_FILE:-NOT FOUND}"
echo "  VerifyContactPage:${VERIFY_FILE:-NOT FOUND}"
echo "  ConsentsPage:     ${CONSENTS_FILE:-NOT FOUND}"
echo "  KycPage:          ${KYC_FILE:-NOT FOUND}"

if [ -z "${ONBOARDING_FILE}" ] || [ -z "${VERIFY_FILE}" ] || [ -z "${CONSENTS_FILE}" ] || [ -z "${KYC_FILE}" ]; then
  echo
  echo "One or more feature page files could not be found."
  echo "Please run:"
  echo "  find apps/web/src -type f \\( -name 'OnboardingPage.tsx' -o -name 'VerifyContactPage.tsx' -o -name 'ConsentsPage.tsx' -o -name 'KycPage.tsx' \\)"
  exit 1
fi

mkdir -p apps/web/pages/app

backup apps/web/pages/app/onboarding.tsx
backup apps/web/pages/app/verify-contact.tsx
backup apps/web/pages/app/consents.tsx
backup apps/web/pages/app/kyc.tsx

PORTAL_IMPORT="../../src/components/portal/PortalShell"
ONBOARDING_IMPORT="$(to_import_path apps/web/pages/app/onboarding.tsx "$ONBOARDING_FILE")"
VERIFY_IMPORT="$(to_import_path apps/web/pages/app/verify-contact.tsx "$VERIFY_FILE")"
CONSENTS_IMPORT="$(to_import_path apps/web/pages/app/consents.tsx "$CONSENTS_FILE")"
KYC_IMPORT="$(to_import_path apps/web/pages/app/kyc.tsx "$KYC_FILE")"

cat > apps/web/pages/app/onboarding.tsx <<EOF
import PortalShell from "${PORTAL_IMPORT}";
import OnboardingPage from "${ONBOARDING_IMPORT}";

export default function OnboardingRoute() {
  return (
    <PortalShell>
      <OnboardingPage />
    </PortalShell>
  );
}
EOF

cat > apps/web/pages/app/verify-contact.tsx <<EOF
import PortalShell from "${PORTAL_IMPORT}";
import VerifyContactPage from "${VERIFY_IMPORT}";

export default function VerifyContactRoute() {
  return (
    <PortalShell>
      <VerifyContactPage />
    </PortalShell>
  );
}
EOF

cat > apps/web/pages/app/consents.tsx <<EOF
import PortalShell from "${PORTAL_IMPORT}";
import ConsentsPage from "${CONSENTS_IMPORT}";

export default function ConsentsRoute() {
  return (
    <PortalShell>
      <ConsentsPage />
    </PortalShell>
  );
}
EOF

cat > apps/web/pages/app/kyc.tsx <<EOF
import PortalShell from "${PORTAL_IMPORT}";
import KycPage from "${KYC_IMPORT}";

export default function KycRoute() {
  return (
    <PortalShell>
      <KycPage />
    </PortalShell>
  );
}
EOF

echo
echo "==> Rebuilt route wrappers with detected import paths."
echo "onboarding -> ${ONBOARDING_IMPORT}"
echo "verify-contact -> ${VERIFY_IMPORT}"
echo "consents -> ${CONSENTS_IMPORT}"
echo "kyc -> ${KYC_IMPORT}"

echo
echo "==> Build check ..."
pnpm --filter web build

echo
echo "✅ PortalShell route import fix applied."
echo
echo "Next:"
echo "  docker compose build web --no-cache"
echo "  docker compose up -d web"
