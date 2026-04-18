#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 1 && -n "${1:-}" ]]; then
  ROOT="$1"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import sys
from textwrap import dedent

root = Path(sys.argv[1])

pkg_path = root / "apps/api/package.json"
dispatch_path = root / "apps/api/src/lib/matching/serialized-dispatch.ts"

for p in [pkg_path, dispatch_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:matching:serialized-dispatch"] = "vitest run test/matching-serialized-dispatch.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

dispatch_path.write_text(dedent("""type TaskFactory<T> = () => Promise<T>;

const lanes = new Map<string, Promise<unknown>>();

export async function runSerializedByKey<T>(
  key: string,
  taskFactory: TaskFactory<T>,
): Promise<T> {
  const previous = lanes.get(key) ?? Promise.resolve();

  const run = previous.catch(() => undefined).then(taskFactory);
  const tracked = run.finally(() => {
    if (lanes.get(key) === tracked) {
      lanes.delete(key);
    }
  });

  lanes.set(key, tracked);
  return tracked;
}

export function buildSymbolModeKey(symbol: string, mode: string): string {
  return `${symbol}:${mode}`;
}

export function getSerializedLaneCount(): number {
  return lanes.size;
}

export function resetSerializedDispatchForTests(): void {
  lanes.clear();
}
"""))

print("Patched apps/api/src/lib/matching/serialized-dispatch.ts so lane cleanup resolves before the awaited tracked promise completes.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 4D fix patch applied."
