#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> 1) Show any remaining createApp references..."
grep -R "createApp" -n apps/api || true

echo
echo "==> 2) Remove stale local build artifacts..."
rm -rf apps/api/dist
rm -rf apps/web/.next

echo
echo "==> 3) Force-clean API Dockerfile build step..."
python3 - <<'PY'
from pathlib import Path

p = Path("apps/api/Dockerfile")
text = p.read_text()

old = "RUN pnpm --filter api build"
new = "RUN rm -rf apps/api/dist && pnpm --filter api build"

if old in text and new not in text:
    text = text.replace(old, new)

p.write_text(text)
PY

echo
echo "==> 4) Comment out api bind-mounts in docker-compose.yml if present..."
python3 - <<'PY'
from pathlib import Path
p = Path("docker-compose.yml")
text = p.read_text().splitlines()

out = []
in_api = False
in_volumes = False
api_indent = None
vol_indent = None

for line in text:
    stripped = line.lstrip()
    indent = len(line) - len(stripped)

    if stripped.startswith("api:") and indent <= 2:
        in_api = True
        api_indent = indent
        in_volumes = False
        vol_indent = None
        out.append(line)
        continue

    if in_api:
        if indent <= api_indent and stripped and not stripped.startswith("#") and not stripped.startswith("api:"):
            in_api = False
            in_volumes = False
            vol_indent = None

    if in_api and stripped.startswith("volumes:"):
        in_volumes = True
        vol_indent = indent
        out.append("# " + line if not stripped.startswith("#") else line)
        continue

    if in_api and in_volumes:
        if indent > vol_indent:
            if stripped.startswith("- ./apps/api") or stripped.startswith("- ./:/app") or stripped.startswith("- ./apps:/app/apps"):
                out.append("# " + line if not stripped.startswith("#") else line)
                continue
        else:
            in_volumes = False
            vol_indent = None

    out.append(line)

p.write_text("\n".join(out) + "\n")
PY

echo
echo "==> 5) Rebuild local API dist to confirm current source compiles to the right runtime..."
pnpm --filter api build

echo
echo "==> 6) Show the first lines of the rebuilt local dist/server.js ..."
sed -n '1,30p' apps/api/dist/server.js || true

echo
echo "✅ Cleanup/patch applied."
echo
echo "Next run manually:"
echo "  docker compose build api --no-cache"
echo "  docker compose up -d api"
echo "  docker compose logs api --tail=120"
echo "  curl http://127.0.0.1:4010/health"
