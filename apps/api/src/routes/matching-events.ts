import express from "express";

import {
  type MatchingEventEnvelope,
  listMatchingEvents,
  listPersistedMatchingEvents,
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
  return `id: ${event.id}\nevent: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`;
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
  res.write(`event: snapshot\ndata: ${JSON.stringify({ events: snapshot })}\n\n`);

  const unsubscribe = subscribeMatchingEvents((event) => {
    if (!matchesFilter(event, symbol, mode)) return;
    res.write(buildSseEventFrame(event));
  });

  const keepAlive = setInterval(() => {
    res.write(": keep-alive\n\n");
  }, 15000);

  req.on("close", () => {
    clearInterval(keepAlive);
    unsubscribe();
    res.end();
  });
});

router.get("/replay", async (req, res) => {
  const symbol = typeof req.query.symbol === "string" ? req.query.symbol : undefined;
  const mode = typeof req.query.mode === "string" ? req.query.mode : undefined;
  const afterEventId =
    typeof req.query.afterEventId === "string" && req.query.afterEventId.length > 0
      ? Number(req.query.afterEventId)
      : undefined;
  const limit =
    typeof req.query.limit === "string" && req.query.limit.length > 0
      ? Number(req.query.limit)
      : 100;

  const events = await listPersistedMatchingEvents({
    symbol,
    mode,
    afterEventId: Number.isFinite(afterEventId) ? afterEventId : undefined,
    limit: Number.isFinite(limit) ? limit : 100,
  });

  return res.json({ ok: true, events });
});

export default router;
