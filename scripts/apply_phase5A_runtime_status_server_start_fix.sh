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
import re
import sys

root = Path(sys.argv[1])

pkg_path = root / "apps/api/package.json"
server_path = root / "apps/api/src/server.ts"

for p in [pkg_path, server_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:runtime:status"] = "vitest run test/runtime-status.lib.test.ts test/runtime-status.routes.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

server_text = server_path.read_text()

import_line = 'import { markRuntimeStarted, markRuntimeStopped } from "./lib/runtime/runtime-status";'
if import_line not in server_text:
    anchor = 'import {\n  startReconciliationWorker,\n  stopReconciliationWorker,\n} from "./workers/reconciliation";'
    if anchor in server_text:
        server_text = server_text.replace(anchor, anchor + '\n' + import_line, 1)
    else:
        raise SystemExit("Could not find reconciliation import anchor in server.ts")

if 'markRuntimeStopped(signal);' not in server_text:
    server_text = server_text.replace(
        '  stopReconciliationWorker();\n',
        '  stopReconciliationWorker();\n  markRuntimeStopped(signal);\n',
        1,
    )

if 'markRuntimeStarted({' not in server_text:
    # First try inserting after reconciliation worker startup block
    block_pattern = re.compile(
        r'(\s*const reconEnabled = .*?\n\s*if \(reconEnabled\) \{\n\s*startReconciliationWorker\(RECON_INTERVAL_MS\);\n\s*\}\n)',
        re.DOTALL,
    )
    if block_pattern.search(server_text):
        server_text = block_pattern.sub(
            lambda m: m.group(1)
            + '\n'
            + '    markRuntimeStarted({\n'
            + '      port: PORT,\n'
            + '      reconciliationEnabled: reconEnabled,\n'
            + '      reconciliationIntervalMs: RECON_INTERVAL_MS,\n'
            + '    });\n',
            server_text,
            count=1,
        )
    else:
        # Fallback: insert after app.listen(...)
        listen_pattern = re.compile(
            r'(\s*server = app\.listen\(PORT, \(\) => \{\n\s*console\.log\(`api listening on \$\{PORT\}`\);\n\s*\}\);\n)',
            re.DOTALL,
        )
        if listen_pattern.search(server_text):
            server_text = listen_pattern.sub(
                lambda m: m.group(1)
                + '\n'
                + '    const reconEnabled = process.env.RECONCILIATION_ENABLED !== "false";\n'
                + '    if (reconEnabled) {\n'
                + '      startReconciliationWorker(RECON_INTERVAL_MS);\n'
                + '    }\n'
                + '\n'
                + '    markRuntimeStarted({\n'
                + '      port: PORT,\n'
                + '      reconciliationEnabled: reconEnabled,\n'
                + '      reconciliationIntervalMs: RECON_INTERVAL_MS,\n'
                + '    });\n',
                server_text,
                count=1,
            )
        else:
            raise SystemExit("Could not find a safe insertion point for markRuntimeStarted(...) in server.ts")

server_path.write_text(server_text)

print("Patched apps/api/src/server.ts to ensure markRuntimeStarted(...) is called after boot for Phase 5A.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 5A server-start fix patch applied."
