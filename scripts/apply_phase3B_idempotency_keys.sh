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
schema_path = root / "apps/api/prisma/schema.prisma"
migration_path = root / "apps/api/prisma/migrations/20260416_phase3b_idempotency_keys/migration.sql"
helper_path = root / "apps/api/src/lib/idempotency.ts"
orders_path = root / "apps/api/src/routes/orders.ts"
test_path = root / "apps/api/test/idempotency.lib.test.ts"

for p in [pkg_path, schema_path, orders_path]:
    if not p.exists():
        raise SystemExit(f"Missing required file: {p}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:lib:idempotency"] = "vitest run test/idempotency.lib.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

schema_text = schema_path.read_text()
if 'model IdempotencyKey {' not in schema_text:
    schema_text = schema_text.rstrip() + "\n\n" + dedent(\"\"\"\
model IdempotencyKey {
  id             String   @id @default(cuid())
  ownerType      String
  ownerId        String
  scope          String
  key            String
  requestHash    String
  method         String
  path           String
  state          String   @default("PENDING")
  responseStatus Int?
  responseBody   Json?
  createdAt      DateTime @default(now())
  updatedAt      DateTime @updatedAt

  @@unique([ownerType, ownerId, scope, key])
  @@index([scope, key])
}
\"\"\")
    schema_path.write_text(schema_text)

migration_sql = dedent(\"\"\"\
-- Phase 3B: persistent idempotency keys for order placement and cancel requests.

CREATE TABLE IF NOT EXISTS "IdempotencyKey" (
  "id" TEXT NOT NULL,
  "ownerType" TEXT NOT NULL,
  "ownerId" TEXT NOT NULL,
  "scope" TEXT NOT NULL,
  "key" TEXT NOT NULL,
  "requestHash" TEXT NOT NULL,
  "method" TEXT NOT NULL,
  "path" TEXT NOT NULL,
  "state" TEXT NOT NULL DEFAULT 'PENDING',
  "responseStatus" INTEGER,
  "responseBody" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "IdempotencyKey_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "IdempotencyKey_ownerType_ownerId_scope_key_key"
  ON "IdempotencyKey"("ownerType", "ownerId", "scope", "key");

CREATE INDEX IF NOT EXISTS "IdempotencyKey_scope_key_idx"
  ON "IdempotencyKey"("scope", "key");
\"\"\")
migration_path.parent.mkdir(parents=True, exist_ok=True)
migration_path.write_text(migration_sql)

helper_ts = dedent(\"\"\"\
import { createHash } from "node:crypto";
import type { Request, Response } from "express";

import { Prisma } from "@prisma/client";

import { prisma } from "./prisma";

type JsonLike =
  | null
  | boolean
  | number
  | string
  | JsonLike[]
  | { [key: string]: JsonLike };

type IdempotencyRecord = {
  ownerType: string;
  ownerId: string;
  scope: string;
  key: string;
  requestHash: string;
  method: string;
  path: string;
};

function stableSerialize(value: unknown): string {
  if (value === null || value === undefined) return "null";
  if (typeof value !== "object") return JSON.stringify(value);

  if (Array.isArray(value)) {
    return "[" + value.map((v) => stableSerialize(v)).join(",") + "]";
  }

  const entries = Object.entries(value as Record<string, unknown>)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([k, v]) => `${JSON.stringify(k)}:${stableSerialize(v)}`);

  return "{" + entries.join(",") + "}";
}

function readIdempotencyKey(req: Request): string | null {
  const raw =
    req.get?.("Idempotency-Key") ??
    req.header?.("Idempotency-Key") ??
    (typeof req.headers["idempotency-key"] === "string"
      ? req.headers["idempotency-key"]
      : Array.isArray(req.headers["idempotency-key"])
        ? req.headers["idempotency-key"][0]
        : null);

  const key = String(raw ?? "").trim();
  return key.length > 0 ? key : null;
}

function getOwner(req: Request): { ownerType: string; ownerId: string } | null {
  const auth = (req as any).auth;
  if (auth?.userId) {
    return { ownerType: "USER", ownerId: String(auth.userId) };
  }

  const principal = (req as any).principal;
  if (principal?.userId) {
    return { ownerType: String(principal.type ?? "AGENT"), ownerId: String(principal.userId) };
  }

  return null;
}

function hashRequest(req: Request): string {
  const payload = {
    method: req.method,
    path: req.path,
    params: req.params ?? {},
    query: req.query ?? {},
    body: req.body ?? {},
  };
  return createHash("sha256").update(stableSerialize(payload)).digest("hex");
}

async function findRecord(input: IdempotencyRecord) {
  return prisma.idempotencyKey.findUnique({
    where: {
      ownerType_ownerId_scope_key: {
        ownerType: input.ownerType,
        ownerId: input.ownerId,
        scope: input.scope,
        key: input.key,
      },
    },
  });
}

async function createPending(input: IdempotencyRecord) {
  return prisma.idempotencyKey.create({
    data: {
      ownerType: input.ownerType,
      ownerId: input.ownerId,
      scope: input.scope,
      key: input.key,
      requestHash: input.requestHash,
      method: input.method,
      path: input.path,
      state: "PENDING",
    },
  });
}

async function markCompleted(
  id: string,
  responseStatus: number,
  responseBody: JsonLike | undefined,
): Promise<void> {
  await prisma.idempotencyKey.update({
    where: { id },
    data: {
      state: "COMPLETED",
      responseStatus,
      responseBody: (responseBody ?? null) as Prisma.InputJsonValue,
    },
  });
}

async function clearPending(id: string): Promise<void> {
  await prisma.idempotencyKey.delete({ where: { id } }).catch(() => undefined);
}

export function withIdempotency(
  scope: string,
  handler: (req: Request, res: Response) => Promise<unknown>,
) {
  return async (req: Request, res: Response) => {
    const key = readIdempotencyKey(req);
    if (!key) {
      return handler(req, res);
    }

    const owner = getOwner(req);
    if (!owner) {
      return res.status(401).json({ error: "Authentication required." });
    }

    const input: IdempotencyRecord = {
      ownerType: owner.ownerType,
      ownerId: owner.ownerId,
      scope,
      key,
      requestHash: hashRequest(req),
      method: req.method,
      path: req.path,
    };

    let existing = await findRecord(input);

    if (existing) {
      if (existing.requestHash !== input.requestHash) {
        return res.status(409).json({
          error: "Idempotency key reuse with different payload.",
        });
      }

      if (existing.state === "COMPLETED") {
        return res.status(existing.responseStatus ?? 200).json(existing.responseBody ?? { ok: true });
      }

      return res.status(409).json({
        error: "Idempotency request is already in progress.",
      });
    }

    try {
      existing = await createPending(input);
    } catch (error: any) {
      if (error?.code === "P2002") {
        existing = await findRecord(input);
        if (existing?.requestHash !== input.requestHash) {
          return res.status(409).json({
            error: "Idempotency key reuse with different payload.",
          });
        }
        if (existing?.state === "COMPLETED") {
          return res.status(existing.responseStatus ?? 200).json(existing.responseBody ?? { ok: true });
        }
        return res.status(409).json({
          error: "Idempotency request is already in progress.",
        });
      }
      throw error;
    }

    let capturedStatus = 200;
    let capturedBody: JsonLike | undefined;

    const originalStatus = res.status.bind(res);
    const originalJson = res.json.bind(res);

    (res as any).status = (code: number) => {
      capturedStatus = code;
      return originalStatus(code);
    };

    (res as any).json = (body: JsonLike) => {
      capturedBody = body;
      return originalJson(body);
    };

    try {
      const result = await handler(req, res);
      await markCompleted(existing.id, capturedStatus, capturedBody);
      return result;
    } catch (error) {
      await clearPending(existing.id);
      throw error;
    }
  };
}
\"\"\")
helper_path.parent.mkdir(parents=True, exist_ok=True)
helper_path.write_text(helper_ts)

orders_text = orders_path.read_text()

if 'import { withIdempotency } from "../lib/idempotency";' not in orders_text:
    anchor = 'import { canCancel, ORDER_STATUS } from "../lib/ledger/order-state";'
    if anchor not in orders_text:
        raise SystemExit("Could not find order-state import anchor in orders.ts")
    orders_text = orders_text.replace(
        anchor,
        anchor + '\nimport { withIdempotency } from "../lib/idempotency";',
        1,
    )

place_old = '''  auditPrivilegedRequest("ORDER_PLACE_REQUESTED", "ORDER"),
  async (req, res) => {'''
place_new = '''  auditPrivilegedRequest("ORDER_PLACE_REQUESTED", "ORDER"),
  withIdempotency("HUMAN_ORDER_PLACE", async (req, res) => {'''
if place_old in orders_text:
    orders_text = orders_text.replace(place_old, place_new, 1)
elif 'withIdempotency("HUMAN_ORDER_PLACE"' not in orders_text:
    raise SystemExit("Could not patch orders.ts placement handler with idempotency.")

place_end_old = '''  },
);

router.post(
  "/:orderId/cancel",'''
place_end_new = '''  }),
);

router.post(
  "/:orderId/cancel",'''
if place_end_old in orders_text:
    orders_text = orders_text.replace(place_end_old, place_end_new, 1)

cancel_old = '''  auditPrivilegedRequest("ORDER_CANCEL_REQUESTED", "ORDER", (req) =>
    String(req.params.orderId),
  ),
  async (req, res) => {'''
cancel_new = '''  auditPrivilegedRequest("ORDER_CANCEL_REQUESTED", "ORDER", (req) =>
    String(req.params.orderId),
  ),
  withIdempotency("HUMAN_ORDER_CANCEL", async (req, res) => {'''
if cancel_old in orders_text:
    orders_text = orders_text.replace(cancel_old, cancel_new, 1)
elif 'withIdempotency("HUMAN_ORDER_CANCEL"' not in orders_text:
    raise SystemExit("Could not patch orders.ts cancel handler with idempotency.")

cancel_end_old = '''  },
);

router.get("/:orderId", async (req, res) => {'''
cancel_end_new = '''  }),
);

router.get("/:orderId", async (req, res) => {'''
if cancel_end_old in orders_text:
    orders_text = orders_text.replace(cancel_end_old, cancel_end_new, 1)

orders_path.write_text(orders_text)

test_ts = dedent(\"\"\"\
import { beforeEach, describe, expect, it, vi } from "vitest";

const store = new Map<string, any>();

const prismaMock = {
  idempotencyKey: {
    findUnique: vi.fn(async ({ where }: any) => {
      const compound = where.ownerType_ownerId_scope_key;
      const key = `${compound.ownerType}:${compound.ownerId}:${compound.scope}:${compound.key}`;
      return store.get(key) ?? null;
    }),
    create: vi.fn(async ({ data }: any) => {
      const key = `${data.ownerType}:${data.ownerId}:${data.scope}:${data.key}`;
      if (store.has(key)) {
        const error: any = new Error("Unique constraint");
        error.code = "P2002";
        throw error;
      }
      const record = { id: `idem-${store.size + 1}`, ...data };
      store.set(key, record);
      return record;
    }),
    update: vi.fn(async ({ where, data }: any) => {
      for (const [k, value] of store.entries()) {
        if (value.id === where.id) {
          const next = { ...value, ...data };
          store.set(k, next);
          return next;
        }
      }
      throw new Error("Record not found");
    }),
    delete: vi.fn(async ({ where }: any) => {
      for (const [k, value] of store.entries()) {
        if (value.id === where.id) {
          store.delete(k);
          return value;
        }
      }
      return null;
    }),
  },
};

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));

import { withIdempotency } from "../src/lib/idempotency";

function makeReq(body: any, key = "idem-1"): any {
  return {
    method: "POST",
    path: "/api/orders",
    params: {},
    query: {},
    body,
    auth: { userId: "user-1" },
    headers: { "idempotency-key": key },
    get(name: string) {
      return this.headers[String(name).toLowerCase()] ?? null;
    },
    header(name: string) {
      return this.get(name);
    },
  };
}

function makeRes(): any {
  const res: any = {};
  res.statusCode = 200;
  res.body = undefined;
  res.status = vi.fn((code: number) => {
    res.statusCode = code;
    return res;
  });
  res.json = vi.fn((body: any) => {
    res.body = body;
    return res;
  });
  return res;
}

describe("idempotency helper", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    store.clear();
  });

  it("replays the stored response for the same key and same payload", async () => {
    const handler = vi.fn(async (_req, res) => {
      return res.status(201).json({ ok: true, orderId: "ord-1" });
    });

    const wrapped = withIdempotency("HUMAN_ORDER_PLACE", handler);

    const req1 = makeReq({ symbol: "BTC-USD", qty: "1", price: "100" }, "same-key");
    const res1 = makeRes();
    await wrapped(req1, res1);

    const req2 = makeReq({ symbol: "BTC-USD", qty: "1", price: "100" }, "same-key");
    const res2 = makeRes();
    await wrapped(req2, res2);

    expect(handler).toHaveBeenCalledTimes(1);
    expect(res1.statusCode).toBe(201);
    expect(res1.body).toEqual({ ok: true, orderId: "ord-1" });
    expect(res2.statusCode).toBe(201);
    expect(res2.body).toEqual({ ok: true, orderId: "ord-1" });
  });

  it("rejects the same key reused with a different payload", async () => {
    const handler = vi.fn(async (_req, res) => {
      return res.status(201).json({ ok: true, orderId: "ord-2" });
    });

    const wrapped = withIdempotency("HUMAN_ORDER_PLACE", handler);

    const req1 = makeReq({ symbol: "BTC-USD", qty: "1", price: "100" }, "same-key");
    const res1 = makeRes();
    await wrapped(req1, res1);

    const req2 = makeReq({ symbol: "BTC-USD", qty: "2", price: "100" }, "same-key");
    const res2 = makeRes();
    await wrapped(req2, res2);

    expect(handler).toHaveBeenCalledTimes(1);
    expect(res2.statusCode).toBe(409);
    expect(res2.body).toEqual(
      expect.objectContaining({
        error: "Idempotency key reuse with different payload.",
      }),
    );
  });

  it("runs normally when no idempotency key is provided", async () => {
    const handler = vi.fn(async (_req, res) => {
      return res.status(201).json({ ok: true });
    });

    const wrapped = withIdempotency("HUMAN_ORDER_PLACE", handler);

    const req = makeReq({ symbol: "BTC-USD" }, "");
    delete req.headers["idempotency-key"];

    await wrapped(req, makeRes());
    await wrapped(req, makeRes());

    expect(handler).toHaveBeenCalledTimes(2);
  });
});
\"\"\")
test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(test_ts)

print("Patched package.json, added persistent idempotency helper + schema/migration, patched orders.ts, and wrote apps/api/test/idempotency.lib.test.ts for Phase 3B.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 3B patch applied."
