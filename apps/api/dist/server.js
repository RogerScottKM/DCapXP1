"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
require("dotenv/config");
const app_1 = __importDefault(require("./app"));
const bootstrap_secrets_1 = require("./lib/bootstrap-secrets");
const prisma_1 = require("./lib/prisma");
const reconciliation_1 = require("./workers/reconciliation");
const PORT = Number(process.env.API_PORT ?? process.env.PORT ?? 4010);
const IS_PRODUCTION = process.env.NODE_ENV === "production";
const RECON_INTERVAL_MS = Number(process.env.RECONCILIATION_INTERVAL_MS ?? (IS_PRODUCTION ? 60_000 : 300_000));
let server = null;
let shuttingDown = false;
function requireEnv(name) {
    if (!process.env[name]?.trim()) {
        throw new Error(`Missing required environment variable: ${name}`);
    }
}
function validateEnv() {
    requireEnv("DATABASE_URL");
    requireEnv("JWT_SECRET");
    requireEnv("OTP_HMAC_SECRET");
    if (IS_PRODUCTION) {
        requireEnv("APP_BASE_URL");
        requireEnv("APP_CORS_ORIGINS");
        requireEnv("EMAIL_FROM");
    }
}
async function shutdown(signal) {
    if (shuttingDown)
        return;
    shuttingDown = true;
    console.log(`[server] received ${signal}, shutting down`);
    (0, reconciliation_1.stopReconciliationWorker)();
    const closeServer = new Promise((resolve) => {
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
        await prisma_1.prisma.$disconnect();
        clearTimeout(forceExitTimer);
        process.exit(0);
    }
    catch (error) {
        clearTimeout(forceExitTimer);
        console.error("[server] shutdown failed", error);
        process.exit(1);
    }
}
async function main() {
    await (0, bootstrap_secrets_1.bootstrapSecrets)();
    validateEnv();
    server = app_1.default.listen(PORT, () => {
        console.log(`api listening on ${PORT}`);
    });
    const reconEnabled = process.env.RECONCILIATION_ENABLED !== "false";
    if (reconEnabled) {
        (0, reconciliation_1.startReconciliationWorker)(RECON_INTERVAL_MS);
    }
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
