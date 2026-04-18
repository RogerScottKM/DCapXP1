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

route_path = root / "apps/api/src/routes/matching-events.ts"
if not route_path.exists():
    raise SystemExit(f"Missing required file: {route_path}")

route_path.write_text(dedent("""\
import express from "express";

import {
  type MatchingEventEnvelope,
  listMatchingEvents,
  subscribeMatchingEvents,
} from "../lib/matching/matching-events";

const router = express.Router();

function matchesFilter(
  event: MatchingEventEnvelope,
  symbol?: string,
  mode?: string,
): boolean {
  if (symbol && event.symbol !== symbol) return false;
  if (mode && event.mode !== mode) return false;
  return true;
}

export function buildSseEventFrame(event: MatchingEventEnvelope): string {
  return `id: ${event.id}\\nevent: ${event.type}\\ndata: ${JSON.stringify(event)}\\n\\n`;
}

router.get("/recent", (req, res) => {
  const symbol = typeof req.query.symbol === "string" ? req.query.symbol : undefined;
  const mode = typeof req.query.mode === "string" ? req.query.mode : undefined;
  const events = listMatchingEvents(200).filter((event) => matchesFilter(event, symbol, mode));
  return res.json({ ok: true, events });
});

router.get("/stream", (req, res) => {
  const symbol = typeof req.query.symbol === "string" ? req.query.symbol : undefined;
  const mode = typeof req.query.mode === "string" ? req.query.mode : undefined;

  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.setHeader("X-Accel-Buffering", "no");
  if (typeof (res as any).flushHeaders === "function") {
    (res as any).flushHeaders();
  }

  const snapshot = listMatchingEvents(200).filter((event) => matchesFilter(event, symbol, mode));
  res.write(`event: snapshot\\ndata: ${JSON.stringify({ events: snapshot })}\\n\\n`);

  const unsubscribe = subscribeMatchingEvents((event) => {
    if (!matchesFilter(event, symbol, mode)) return;
    res.write(buildSseEventFrame(event));
  });

  const keepAlive = setInterval(() => {
    res.write(": keep-alive\\n\\n");
  }, 15000);

  req.on("close", () => {
    clearInterval(keepAlive);
    unsubscribe();
    res.end();
  });
});

export default router;
"""))

print("Rewrote apps/api/src/routes/matching-events.ts with properly escaped SSE frames and keep-alive writes for Phase 4F.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 4F route-fix patch applied."
