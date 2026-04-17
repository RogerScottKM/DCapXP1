import "dotenv/config";
import type { Server } from "http";

import app from "./app";
import { bootstrapSecrets } from "./lib/bootstrap-secrets";
import { prisma } from "./lib/prisma";
import {
  startReconciliationWorker,
  stopReconciliationWorker,
} from "./workers/reconciliation";
import { markRuntimeStarted, markRuntimeStopped } from "./lib/runtime/runtime-status";

const PORT = Number(process.env.API_PORT ?? process.env.PORT ?? 4010);
const IS_PRODUCTION = process.env.NODE_ENV === "production";
const RECON_INTERVAL_MS = Number(
  process.env.RECONCILIATION_INTERVAL_MS ?? (IS_PRODUCTION ? 60_000 : 300_000),
);

let server: Server | null = null;
let shuttingDown = false;

function requireEnv(name: string): void {
  if (!process.env[name]?.trim()) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
}

function validateEnv(): void {
  requireEnv("DATABASE_URL");
  requireEnv("JWT_SECRET");
  requireEnv("OTP_HMAC_SECRET");
  if (IS_PRODUCTION) {
    requireEnv("APP_BASE_URL");
    requireEnv("APP_CORS_ORIGINS");
    requireEnv("EMAIL_FROM");
  }
}

async function shutdown(signal: string): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;

  console.log(`[server] received ${signal}, shutting down`);

  stopReconciliationWorker();
  markRuntimeStopped(signal);

  const closeServer = new Promise<void>((resolve) => {
    if (!server) {
      resolve();
      return;
    }
    server.close(() => resolve());
  });

  const forceExitTimer = setTimeout(() => {
    console.error("[server] forced shutdown after timeout");
    process.exit(1);
  }, 30_000);

  try {
    await closeServer;
    await prisma.$disconnect();
    clearTimeout(forceExitTimer);
    process.exit(0);
  } catch (error) {
    clearTimeout(forceExitTimer);
    console.error("[server] shutdown failed", error);
    process.exit(1);
  }
}

async function main(): Promise<void> {
  await bootstrapSecrets();
  validateEnv();

  server = app.listen(PORT, () => {
    console.log(`api listening on ${PORT}`);
  });

  const reconEnabled = process.env.RECONCILIATION_ENABLED !== "false";
  if (reconEnabled) {
    startReconciliationWorker(RECON_INTERVAL_MS);
  }

    markRuntimeStarted({
      port: PORT,
      reconciliationEnabled: reconEnabled,
      reconciliationIntervalMs: RECON_INTERVAL_MS,
    });
}

void main().catch((error) => {
  console.error("[server] startup failed", error);
  process.exit(1);
});

process.on("SIGTERM", () => {
  void shutdown("SIGTERM");
});
process.on("SIGINT", () => {
  void shutdown("SIGINT");
});
process.on("unhandledRejection", (error) => {
  console.error("unhandledRejection", error);
});
process.on("uncaughtException", (error) => {
  console.error("uncaughtException", error);
  void shutdown("uncaughtException");
});
