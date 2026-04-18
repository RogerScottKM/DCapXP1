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
import sys
from textwrap import dedent

root = Path(sys.argv[1])

test_path = root / "apps/api/test/in-memory-settlement-integration.test.ts"
if not test_path.exists():
    raise SystemExit(f"Missing required file: {test_path}")

test_text = test_path.read_text()

old_block = dedent("""\
    getOrderRemainingQty
      .mockResolvedValueOnce(new Decimal("3"))
      .mockResolvedValueOnce(new Decimal("2"))
      .mockResolvedValueOnce(new Decimal("2"));
""")

new_block = dedent("""\
    getOrderRemainingQty
      .mockResolvedValueOnce(new Decimal("3")) // first execute: sell order initial remaining
      .mockResolvedValueOnce(new Decimal("3")) // first execute: sell order final refresh remaining
      .mockResolvedValueOnce(new Decimal("2")) // second execute: buy order initial remaining
      .mockResolvedValueOnce(new Decimal("0")); // second execute: buy order final refresh remaining after full fill
""")

if old_block in test_text:
    test_text = test_text.replace(old_block, new_block, 1)
else:
    # fallback: patch by regex-ish simpler replacement
    if '.mockResolvedValueOnce(new Decimal("3"))' in test_text and '.mockResolvedValueOnce(new Decimal("2"))' in test_text:
        import re
        pattern = re.compile(
            r'getOrderRemainingQty\s*\n\s*\.mockResolvedValueOnce\(new Decimal\("3"\)\)\s*\n\s*\.mockResolvedValueOnce\(new Decimal\("2"\)\)\s*\n\s*\.mockResolvedValueOnce\(new Decimal\("2"\)\);',
            re.MULTILINE,
        )
        replacement = new_block.rstrip()
        test_text, count = pattern.subn(replacement, test_text, count=1)
        if count == 0:
            raise SystemExit("Could not patch getOrderRemainingQty mock sequence in in-memory-settlement-integration.test.ts")
    else:
        raise SystemExit("Could not locate getOrderRemainingQty mock sequence in in-memory-settlement-integration.test.ts")

test_path.write_text(test_text)

print("Patched apps/api/test/in-memory-settlement-integration.test.ts with the full getOrderRemainingQty mock sequence for Phase 4C.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 4C test-fix patch applied."
