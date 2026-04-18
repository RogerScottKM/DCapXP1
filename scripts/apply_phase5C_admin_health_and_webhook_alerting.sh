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
worker_path = root / "apps/api/src/workers/reconciliation.ts"
app_path = root / "apps/api/src/app.ts"
alerting_path = root / "apps/api/src/lib/runtime/alerting.ts"
route_path = root / "apps/api/src/routes/admin-health.ts"
test_alerting_path = root / "apps/api/test/runtime-alerting.lib.test.ts"
test_route_path = root / "apps/api/test/admin-health.routes.test.ts"

for p in [pkg_path, worker_path, app_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:runtime:health"] = "vitest run test/runtime-alerting.lib.test.ts test/admin-health.routes.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

alerting_path.parent.mkdir(parents=True, exist_ok=True)
alerting_path.write_text(dedent("""export type RuntimeAlertInput = {
  type: "RECONCILIATION_FAILURE" | "RUNTIME_ALERT";
  summary: string;
  payload: Record<string, unknown>;
};

export type RuntimeAlertDispatchResult = {
  sent: boolean;
  skipped: boolean;
  status?: number;
};

export function getAlertWebhookUrl(): string | null {
  const value = process.env.ALERT_WEBHOOK_URL?.trim();
  return value ? value : null;
}

export function isAlertingEnabled(): boolean {
  return Boolean(getAlertWebhookUrl());
}

export async function dispatchRuntimeAlert(
  input: RuntimeAlertInput,
  fetchImpl: typeof fetch = fetch,
): Promise<RuntimeAlertDispatchResult> {
  const webhookUrl = getAlertWebhookUrl();
  if (!webhookUrl) {
    return { sent: false, skipped: true };
  }

  const response = await fetchImpl(webhookUrl, {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body: JSON.stringify({
      ts: new Date().toISOString(),
      ...input,
    }),
  });

  return {
    sent: response.ok,
    skipped: false,
    status: response.status,
  };
}
"""))

worker_text = worker_path.read_text()
import_line = 'import { dispatchRuntimeAlert } from "../lib/runtime/alerting";'
if import_line not in worker_text:
    anchor = 'import { noteReconciliationRun } from "../lib/runtime/runtime-status";'
    if anchor not in worker_text:
        raise SystemExit("Could not find runtime-status import anchor in reconciliation.ts")
    worker_text = worker_text.replace(anchor, anchor + '\n' + import_line, 1)

alert_block = dedent("""  const runtimeFailures = allResults.filter((result) => !result.ok);
  if (runtimeFailures.length > 0) {
    await dispatchRuntimeAlert({
      type: "RECONCILIATION_FAILURE",
      summary: `[reconciliation] ${runtimeFailures.length} check(s) failed`,
      payload: {
        failureCount: runtimeFailures.length,
        checkCount: allResults.length,
        failures: runtimeFailures.slice(0, 10),
      },
    }).catch(() => undefined);
  }

""")

if 'type: "RECONCILIATION_FAILURE"' not in worker_text:
    anchor = '  noteReconciliationRun(allResults);\n'
    if anchor not in worker_text:
        raise SystemExit("Could not find noteReconciliationRun anchor in reconciliation.ts")
    worker_text = worker_text.replace(anchor, anchor + alert_block, 1)

worker_path.write_text(worker_text)

route_path.write_text(dedent("""import { Router } from "express";

import {
  getMatchingEventListenerCount,
  listMatchingEvents,
} from "../lib/matching/matching-events";
import { getRuntimeStatus } from "../lib/runtime/runtime-status";
import { requireAuth, requireAdminRecentMfa } from "../middleware/require-auth";

const router = Router();

router.use(requireAuth);

router.get("/", requireAdminRecentMfa(), (_req, res) => {
  const status = getRuntimeStatus();
  const recentEvents = listMatchingEvents(50);
  const lastReconciliationEnvelope =
    [...recentEvents].reverse().find((event) => event.type === "RECONCILIATION_RESULT") ?? null;

  return res.json({
    ok: true,
    health: {
      runtime: status,
      activeSerializedLanes: status.activeSerializedLanes,
      subscriberCount: getMatchingEventListenerCount(),
      recentEventCount: recentEvents.length,
      lastReconciliation:
        lastReconciliationEnvelope?.payload ?? {
          ok: status.lastReconciliationOk,
          failureCount: status.lastReconciliationFailureCount,
          checkCount: status.lastReconciliationCheckCount,
          ts: status.lastReconciliationAt,
        },
    },
  });
});

export default router;
"""))

app_text = app_path.read_text()
if 'import adminHealthRoutes from "./routes/admin-health";' not in app_text:
    import_anchor = None
    for candidate in [
        'import runtimeStatusRoutes from "./routes/runtime-status";',
        'import matchingEventsRoutes from "./routes/matching-events";',
        'import reconciliationRoutes from "./routes/reconciliation";',
    ]:
        if candidate in app_text:
            import_anchor = candidate
            break
    if import_anchor is None:
        raise SystemExit("Could not find route import anchor in app.ts")
    app_text = app_text.replace(
        import_anchor,
        import_anchor + '\nimport adminHealthRoutes from "./routes/admin-health";',
        1,
    )

if 'app.use("/api/admin/health", adminHealthRoutes);' not in app_text:
    export_anchor = 'export default app;'
    if export_anchor not in app_text:
        raise SystemExit("Could not find export anchor in app.ts")
    mount_block = '\n// ── Admin health routes ───────────────────────────────────\napp.use("/api/admin/health", adminHealthRoutes);\n'
    app_text = app_text.replace(export_anchor, mount_block + '\n' + export_anchor, 1)

app_path.write_text(app_text)

test_alerting_path.write_text(dedent("""import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  dispatchRuntimeAlert,
  getAlertWebhookUrl,
  isAlertingEnabled,
} from "../src/lib/runtime/alerting";

describe("runtime alerting", () => {
  beforeEach(() => {
    delete process.env.ALERT_WEBHOOK_URL;
  });

  it("skips dispatch when no webhook is configured", async () => {
    expect(getAlertWebhookUrl()).toBeNull();
    expect(isAlertingEnabled()).toBe(false);

    const result = await dispatchRuntimeAlert({
      type: "RECONCILIATION_FAILURE",
      summary: "test",
      payload: { checkCount: 4 },
    }, vi.fn() as any);

    expect(result).toEqual({ sent: false, skipped: true });
  });

  it("posts alert payloads when a webhook is configured", async () => {
    process.env.ALERT_WEBHOOK_URL = "https://alerts.example.test/hook";
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 202,
    });

    const result = await dispatchRuntimeAlert({
      type: "RECONCILIATION_FAILURE",
      summary: "reconciliation failed",
      payload: { failureCount: 2 },
    }, fetchMock as any);

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0][0]).toBe("https://alerts.example.test/hook");
    expect(result).toEqual({ sent: true, skipped: false, status: 202 });
  });
});
"""))

test_route_path.write_text(dedent("""import express from "express";
import request from "supertest";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { getRuntimeStatus, getMatchingEventListenerCount, listMatchingEvents } = vi.hoisted(() => ({
  getRuntimeStatus: vi.fn(),
  getMatchingEventListenerCount: vi.fn(),
  listMatchingEvents: vi.fn(),
}));

vi.mock("../src/lib/runtime/runtime-status", () => ({
  getRuntimeStatus,
}));

vi.mock("../src/lib/matching/matching-events", () => ({
  getMatchingEventListenerCount,
  listMatchingEvents,
}));

vi.mock("../src/middleware/require-auth", () => ({
  requireAuth: (req: any, res: any, next: any) => {
    if (req.headers["x-auth"] === "1") return next();
    return res.status(401).json({ error: "UNAUTHENTICATED" });
  },
  requireAdminRecentMfa: () => (req: any, res: any, next: any) => {
    if (req.headers["x-admin"] === "1") return next();
    return res.status(403).json({ error: "FORBIDDEN" });
  },
}));

import adminHealthRoutes from "../src/routes/admin-health";

describe("admin health routes", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    getRuntimeStatus.mockReturnValue({
      started: true,
      startedAt: "2026-01-01T00:00:00.000Z",
      stoppedAt: null,
      stopReason: null,
      port: 4010,
      reconciliationEnabled: true,
      reconciliationIntervalMs: 60000,
      lastReconciliationAt: "2026-01-01T00:01:00.000Z",
      lastReconciliationOk: false,
      lastReconciliationFailureCount: 1,
      lastReconciliationCheckCount: 4,
      activeSerializedLanes: 2,
      matchingEventCount: 17,
      lastEventId: 17,
    });
    getMatchingEventListenerCount.mockReturnValue(3);
    listMatchingEvents.mockReturnValue([
      { id: 16, type: "RUNTIME_STATUS", payload: { status: "STARTED" } },
      { id: 17, type: "RECONCILIATION_RESULT", payload: { ok: false, failureCount: 1, checkCount: 4 } },
    ]);
  });

  it("returns 401 without an authenticated session", async () => {
    const app = express();
    app.use("/api/admin/health", adminHealthRoutes);

    const response = await request(app).get("/api/admin/health");

    expect(response.status).toBe(401);
  });

  it("returns 403 for a non-admin request", async () => {
    const app = express();
    app.use("/api/admin/health", adminHealthRoutes);

    const response = await request(app)
      .get("/api/admin/health")
      .set("x-auth", "1");

    expect(response.status).toBe(403);
  });

  it("returns admin health including runtime and subscriber metrics", async () => {
    const app = express();
    app.use("/api/admin/health", adminHealthRoutes);

    const response = await request(app)
      .get("/api/admin/health")
      .set("x-auth", "1")
      .set("x-admin", "1");

    expect(response.status).toBe(200);
    expect(response.body.ok).toBe(true);
    expect(response.body.health.activeSerializedLanes).toBe(2);
    expect(response.body.health.subscriberCount).toBe(3);
    expect(response.body.health.lastReconciliation.failureCount).toBe(1);
  });
});
"""))

print("Patched package.json, added admin-health route and runtime alerting helper, wired reconciliation failures to webhook dispatch, and wrote focused Phase 5C tests.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 5C patch applied."
