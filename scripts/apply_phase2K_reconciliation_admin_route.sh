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
app_path = root / "apps/api/src/app.ts"
route_path = root / "apps/api/src/routes/reconciliation.ts"
test_path = root / "apps/api/test/reconciliation.routes.test.ts"

if not pkg_path.exists():
    raise SystemExit(f"Missing package.json: {pkg_path}")
if not app_path.exists():
    raise SystemExit(f"Missing app.ts: {app_path}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:routes:reconciliation"] = "vitest run test/reconciliation.routes.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

route_ts = dedent("""import { Router } from "express";

import { runReconciliation } from "../workers/reconciliation";
import { auditPrivilegedRequest } from "../middleware/audit-privileged";
import { requireRecentMfa, requireRole } from "../middleware/require-auth";

const router = Router();

router.post(
  "/run",
  requireRole("ADMIN"),
  requireRecentMfa(),
  auditPrivilegedRequest("RECONCILIATION_RUN_REQUESTED", "LEDGER"),
  async (_req, res) => {
    try {
      const results = await runReconciliation();
      const failures = results.filter((r) => !r.ok);

      return res.json({
        ok: failures.length === 0,
        resultCount: results.length,
        failureCount: failures.length,
        results,
      });
    } catch (error: any) {
      return res.status(500).json({
        error: error?.message ?? "Unable to run reconciliation",
      });
    }
  },
);

export default router;
""")
route_path.parent.mkdir(parents=True, exist_ok=True)
route_path.write_text(route_ts)

app_text = app_path.read_text()

if 'import reconciliationRoutes from "./routes/reconciliation";' not in app_text:
    trade_import = 'import tradeRoutes from "./routes/trade";'
    if trade_import not in app_text:
        raise SystemExit("Could not find tradeRoutes import anchor in app.ts")
    app_text = app_text.replace(
        trade_import,
        trade_import + ' import reconciliationRoutes from "./routes/reconciliation";',
        1,
    )

mount_block = 'for (const prefix of ["/api/admin/reconciliation"]) { app.use(prefix, reconciliationRoutes); }'
if mount_block not in app_text:
    not_found_anchor = 'app.use((req, res) => {'
    if not_found_anchor not in app_text:
        raise SystemExit("Could not find 404 handler anchor in app.ts")
    app_text = app_text.replace(
        not_found_anchor,
        mount_block + ' ' + not_found_anchor,
        1,
    )

app_path.write_text(app_text)

test_ts = dedent("""import express from "express";
import request from "supertest";
import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  prismaMock,
  recordSecurityAudit,
  resolveAuthFromRequest,
  runReconciliation,
} = vi.hoisted(() => ({
  prismaMock: {
    roleAssignment: { findMany: vi.fn() },
  },
  recordSecurityAudit: vi.fn(),
  resolveAuthFromRequest: vi.fn(),
  runReconciliation: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/service/security-audit", () => ({ recordSecurityAudit }));
vi.mock("../src/modules/auth/auth.service", () => ({
  authService: { resolveAuthFromRequest },
}));
vi.mock("../src/workers/reconciliation", () => ({
  runReconciliation,
}));
vi.mock("../src/middleware/audit-privileged", () => ({
  auditPrivilegedRequest: () => (_req: any, _res: any, next: (err?: unknown) => void) => next(),
}));

import reconciliationRoutes from "../src/routes/reconciliation";

describe("reconciliation routes", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    resolveAuthFromRequest.mockResolvedValue(null);
    prismaMock.roleAssignment.findMany.mockResolvedValue([]);
  });

  function makeApp() {
    const app = express();
    app.use(express.json());
    app.use("/api/admin/reconciliation", reconciliationRoutes);
    return app;
  }

  it("POST /api/admin/reconciliation/run returns 401 without a session", async () => {
    const app = makeApp();

    const res = await request(app).post("/api/admin/reconciliation/run");

    expect(res.status).toBe(401);
  });

  it("POST /api/admin/reconciliation/run returns 403 for a non-admin user", async () => {
    const app = makeApp();

    resolveAuthFromRequest.mockResolvedValue({
      userId: "user-1",
      sessionId: "session-1",
      mfaMethod: "TOTP",
      mfaVerifiedAt: new Date(),
    });
    prismaMock.roleAssignment.findMany.mockResolvedValue([{ roleCode: "USER" }]);

    const res = await request(app).post("/api/admin/reconciliation/run");

    expect(res.status).toBe(403);
  });

  it("POST /api/admin/reconciliation/run returns 200 for an admin with recent MFA", async () => {
    const app = makeApp();

    resolveAuthFromRequest.mockResolvedValue({
      userId: "admin-1",
      sessionId: "session-1",
      mfaMethod: "TOTP",
      mfaVerifiedAt: new Date(),
    });
    prismaMock.roleAssignment.findMany.mockResolvedValue([{ roleCode: "ADMIN" }]);
    runReconciliation.mockResolvedValue([
      { check: "GLOBAL_BALANCE:USD", ok: true },
      { check: "RECENT_TRADE_SETTLEMENT", ok: false },
    ]);

    const res = await request(app).post("/api/admin/reconciliation/run");

    expect(res.status).toBe(200);
    expect(runReconciliation).toHaveBeenCalledTimes(1);
    expect(res.body).toEqual(
      expect.objectContaining({
        ok: False,
        resultCount: 2,
        failureCount: 1,
      }),
    );
  });
});
""")

# fix JS boolean
test_ts = test_ts.replace("False", "false")

test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(test_ts)

print("Patched package.json, wrote reconciliation.ts, mounted /api/admin/reconciliation in app.ts, and wrote apps/api/test/reconciliation.routes.test.ts for Phase 2K.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 2K patch applied."
