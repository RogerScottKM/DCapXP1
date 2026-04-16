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
server_path = root / "apps/api/src/server.ts"
test_path = root / "apps/api/test/reconciliation.worker.test.ts"

if not pkg_path.exists():
    raise SystemExit(f"Missing package.json: {pkg_path}")
if not server_path.exists():
    raise SystemExit(f"Missing server.ts: {server_path}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:workers:reconciliation"] = "vitest run test/reconciliation.worker.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

server_ts = dedent('''import "dotenv/config";
import type { Server } from "http";
import type { Express } from "express";

import { bootstrapSecrets } from "./lib/bootstrap-secrets";
import { prisma } from "./lib/prisma";
import {
  startReconciliationWorker,
  stopReconciliationWorker,
} from "./workers/reconciliation";

const PORT = Number(process.env.API_PORT ?? process.env.PORT ?? 4010);
const IS_PRODUCTION = process.env.NODE_ENV === "production";
const RECON_INTERVAL_MS = Number(
  process.env.RECONCILIATION_INTERVAL_MS ?? (IS_PRODUCTION ? 60_000 : 300_000),
);

let server: Server | null = null;
let shuttingDown = false;
let prismaClient: { $disconnect(): Promise<void> } | null = null;

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
  if (shuttingDown) {
    return;
  }
  shuttingDown = true;
  console.log(`[server] received ${signal}, shutting down`);

  stopReconciliationWorker();

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
    if (prismaClient) {
      await prismaClient.$disconnect();
    }
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

  const appModule = await import("./app.js");
  const app = appModule.default as unknown as Express;

  prismaClient = prisma;

  server = app.listen(PORT, () => {
    console.log(`api listening on ${PORT}`);
  });

  const reconEnabled = process.env.RECONCILIATION_ENABLED !== "false";
  if (reconEnabled) {
    startReconciliationWorker(RECON_INTERVAL_MS);
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
''')
server_path.write_text(server_ts)

test_ts = dedent('''import { beforeEach, describe, expect, it, vi } from "vitest";

const { prismaMock, recordSecurityAudit } = vi.hoisted(() => ({
  prismaMock: {
    $queryRaw: vi.fn(),
    trade: { findMany: vi.fn(), aggregate: vi.fn() },
    ledgerTransaction: { findMany: vi.fn() },
    order: { findMany: vi.fn() },
  },
  recordSecurityAudit: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/service/security-audit", () => ({ recordSecurityAudit }));

import { runReconciliation } from "../src/workers/reconciliation";

describe("reconciliation worker", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("passes all checks on a healthy empty ledger", async () => {
    prismaMock.$queryRaw.mockResolvedValueOnce([]);
    prismaMock.$queryRaw.mockResolvedValueOnce([]);
    prismaMock.trade.findMany.mockResolvedValue([]);
    prismaMock.order.findMany.mockResolvedValue([]);

    const results = await runReconciliation();

    const failures = results.filter((r) => !r.ok);
    expect(failures).toHaveLength(0);
    expect(recordSecurityAudit).not.toHaveBeenCalled();
  });

  it("detects global balance mismatch and logs audit event", async () => {
    prismaMock.$queryRaw.mockResolvedValueOnce([
      { assetCode: "USD", total_debit: "1005.00", total_credit: "1000.00" },
    ]);
    prismaMock.$queryRaw.mockResolvedValueOnce([]);
    prismaMock.trade.findMany.mockResolvedValue([]);
    prismaMock.order.findMany.mockResolvedValue([]);

    const results = await runReconciliation();

    const failures = results.filter((r) => !r.ok);
    expect(failures.length).toBeGreaterThanOrEqual(1);
    expect(failures[0].check).toContain("GLOBAL_BALANCE");

    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "RECONCILIATION_FAILURE",
        resourceType: "LEDGER",
      }),
    );
  });

  it("detects negative account balances", async () => {
    prismaMock.$queryRaw.mockResolvedValueOnce([
      { assetCode: "USD", total_debit: "1000.00", total_credit: "1000.00" },
    ]);
    prismaMock.$queryRaw.mockResolvedValueOnce([
      {
        accountId: "acct-1",
        ownerType: "USER",
        ownerRef: "user-1",
        assetCode: "USD",
        accountType: "USER_AVAILABLE",
        net_balance: "-50.00",
      },
    ]);
    prismaMock.trade.findMany.mockResolvedValue([]);
    prismaMock.order.findMany.mockResolvedValue([]);

    const results = await runReconciliation();

    const negativeCheck = results.find((r) => r.check.startsWith("NEGATIVE_BALANCE"));
    expect(negativeCheck).toBeDefined();
    expect(negativeCheck!.ok).toBe(false);
  });

  it("detects missing trade settlements", async () => {
    prismaMock.$queryRaw.mockResolvedValueOnce([
      { assetCode: "USD", total_debit: "500", total_credit: "500" },
    ]);
    prismaMock.$queryRaw.mockResolvedValueOnce([]);
    prismaMock.trade.findMany.mockResolvedValue([
      { id: 1n, createdAt: new Date() },
      { id: 2n, createdAt: new Date() },
    ]);
    prismaMock.ledgerTransaction.findMany.mockResolvedValue([
      { referenceId: "1:FILL_SETTLEMENT" },
    ]);
    prismaMock.order.findMany.mockResolvedValue([]);

    const results = await runReconciliation();

    const tradeCheck = results.find((r) => r.check === "RECENT_TRADE_SETTLEMENT");
    expect(tradeCheck).toBeDefined();
    expect(tradeCheck!.ok).toBe(false);
    expect((tradeCheck!.details as any).missingSettlements).toBe(1);
  });
});
''')
test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(test_ts)

print("Patched package.json, rewrote server.ts for worker boot/shutdown integration, and wrote apps/api/test/reconciliation.worker.test.ts for Phase 2L.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 2L patch applied."
