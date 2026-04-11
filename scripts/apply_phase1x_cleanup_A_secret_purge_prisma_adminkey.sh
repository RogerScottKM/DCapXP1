#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])


def read(path: Path) -> str:
    return path.read_text() if path.exists() else ""


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)

# 1) Secret purge in working tree
secret_dir = root / "apps/api/secrets"
secret_dir.mkdir(parents=True, exist_ok=True)
secret_path = secret_dir / "agent_cmmcxp5so0002n86wsrcajdgp_private.pem"
if secret_path.exists():
    secret_path.unlink()
(secret_dir / ".gitkeep").touch(exist_ok=True)

# 2) .gitignore hardening
ignore_path = root / ".gitignore"
ignore = read(ignore_path)
additions = """
# ─── Secrets & private keys ──────────────────────────────
*.pem
*.key
*.p12
*.pfx
*.jks
secrets/
!secrets/.gitkeep

# ─── Docker compose backups (use git branches instead) ───
docker-compose-backup*.yml
docker-compose.yml.bak*
""".strip("\n")
if additions not in ignore:
    if ignore and not ignore.endswith("\n"):
        ignore += "\n"
    ignore += "\n" + additions + "\n"
write(ignore_path, ignore)

# 3) Canonical Prisma singleton
lib_prisma = root / "apps/api/src/lib/prisma.ts"
lib_prisma_text = '''import { PrismaClient } from "@prisma/client";

type GlobalPrisma = typeof globalThis & {
  __dcapxPrisma?: PrismaClient;
};

const globalForPrisma = globalThis as GlobalPrisma;

export const prisma = globalForPrisma.__dcapxPrisma ?? new PrismaClient();

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.__dcapxPrisma = prisma;
}

export default prisma;
'''
write(lib_prisma, lib_prisma_text)

src_prisma = root / "apps/api/src/prisma.ts"
write(src_prisma, 'export { prisma, default } from "./lib/prisma";\n')

infra_prisma = root / "apps/api/src/infra/prisma.ts"
write(infra_prisma, 'export { prisma, default } from "../lib/prisma";\n')

# 4) Admin key fallback removal
admin_key = root / "apps/api/src/infra/adminKey.ts"
admin_key_text = '''export function getAdminKey(): string {
  const key = process.env.ADMIN_KEY?.trim();
  if (!key) {
    throw new Error("ADMIN_KEY is required");
  }
  return key;
}

export default getAdminKey;
'''
write(admin_key, admin_key_text)

print("Patched .gitignore, removed committed private key from working tree, consolidated Prisma client, and removed ADMIN_KEY fallback.")
PY

echo "Phase 1.x Cleanup A applied."
echo "Next important manual step: rotate the compromised agent key and consider git history rewrite (filter-repo/BFG) because deletion from HEAD does not erase public history."
