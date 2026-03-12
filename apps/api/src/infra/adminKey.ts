// apps/api/src/infra/adminKey.ts
import type express from "express";

export function getAdminKey() {
  return process.env.ADMIN_KEY ?? "change-me-now-please";
}

export function isAdmin(req: express.Request) {
  const k = req.header("x-admin-key");
  return Boolean(k) && k === getAdminKey();
}
