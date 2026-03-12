// apps/api/src/infra/mode.ts
import type express from "express";

export type TradeMode = "PAPER" | "LIVE";

export function resolveMode(req: express.Request): TradeMode {
  const raw = String(
    req.header("x-mode") ??
      (req.query.mode as string | undefined) ??
      (req.body?.mode as string | undefined) ??
      "PAPER"
  );

  const m = raw.toUpperCase().trim();
  return m === "LIVE" ? "LIVE" : "PAPER";
}
