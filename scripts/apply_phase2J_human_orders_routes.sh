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
import re
import sys
from textwrap import dedent

root = Path(sys.argv[1])

pkg_path = root / "apps/api/package.json"
app_path = root / "apps/api/src/app.ts"
orders_path = root / "apps/api/src/routes/orders.ts"
test_path = root / "apps/api/test/orders.routes.test.ts"

if not pkg_path.exists():
    raise SystemExit(f"Missing package.json: {pkg_path}")
if not app_path.exists():
    raise SystemExit(f"Missing app.ts: {app_path}")

pkg = json.loads(pkg_path.read_text())
scripts = pkg.setdefault("scripts", {})
scripts["test:routes:orders"] = "vitest run test/orders.routes.test.ts"
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

orders_ts = dedent("""import { Router } from "express";

import { Prisma, TradeMode } from "@prisma/client";
import { Decimal } from "@prisma/client/runtime/library";
import { z } from "zod";

import { prisma } from "../lib/prisma";
import {
  executeLimitOrderAgainstBook,
  getOrderRemainingQty,
  reconcileOrderExecution,
  releaseOrderOnCancel,
  reserveOrderOnPlacement,
} from "../lib/ledger";
import { canCancel, ORDER_STATUS } from "../lib/ledger/order-state";
import { requireAuth, requireRecentMfa, requireLiveModeEligible } from "../middleware/require-auth";
import { auditPrivilegedRequest } from "../middleware/audit-privileged";
import { simpleRateLimit } from "../middleware/simple-rate-limit";

const router = Router();

const orderLimiter = simpleRateLimit({
  keyPrefix: "orders:place",
  windowMs: 60 * 1000,
  max: 30,
});

const cancelLimiter = simpleRateLimit({
  keyPrefix: "orders:cancel",
  windowMs: 60 * 1000,
  max: 60,
});

const placeOrderSchema = z.object({
  symbol: z.string().min(3).max(40),
  side: z.enum(["BUY", "SELL"]),
  type: z.enum(["LIMIT"]),
  price: z.string().refine(
    (v) => {
      try {
        return new Decimal(v).greaterThan(0);
      } catch {
        return false;
      }
    },
    { message: "Price must be a positive number." },
  ),
  qty: z.string().refine(
    (v) => {
      try {
        return new Decimal(v).greaterThan(0);
      } catch {
        return false;
      }
    },
    { message: "Quantity must be a positive number." },
  ),
  mode: z.enum(["PAPER", "LIVE"]).optional().default("PAPER"),
  quoteFeeBps: z.string().optional().default("0"),
});

router.use(requireAuth);

router.get("/", async (req, res) => {
  try {
    const userId = req.auth!.userId;
    const symbol = typeof req.query.symbol === "string" ? req.query.symbol.toUpperCase().trim() : undefined;
    const status = typeof req.query.status === "string" ? req.query.status.toUpperCase().trim() : undefined;
    const mode = typeof req.query.mode === "string" ? req.query.mode.toUpperCase().trim() : undefined;
    const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 200);

    const where: Prisma.OrderWhereInput = { userId };
    if (symbol) where.symbol = symbol;
    if (status) where.status = status as any;
    if (mode === "PAPER" || mode === "LIVE") where.mode = mode as TradeMode;

    const orders = await prisma.order.findMany({
      where,
      orderBy: { createdAt: "desc" },
      take: limit,
    });

    return res.json({
      ok: true,
      orders: orders.map((o) => ({
        id: o.id.toString(),
        symbol: o.symbol,
        side: o.side,
        price: o.price.toString(),
        qty: o.qty.toString(),
        status: o.status,
        mode: o.mode,
        createdAt: o.createdAt.toISOString(),
      })),
    });
  } catch (error: any) {
    return res.status(500).json({ error: error?.message ?? "Unable to fetch orders" });
  }
});

router.post(
  "/",
  requireRecentMfa(),
  requireLiveModeEligible(),
  orderLimiter,
  auditPrivilegedRequest("ORDER_PLACE_REQUESTED", "ORDER"),
  async (req, res) => {
    try {
      const userId = req.auth!.userId;
      const payload = placeOrderSchema.parse(req.body);

      const market = await prisma.market.findUnique({
        where: { symbol: payload.symbol },
      });
      if (!market) {
        return res.status(400).json({ error: `Market ${payload.symbol} not found.` });
      }

      const result = await prisma.$transaction(async (tx) => {
        const order = await tx.order.create({
          data: {
            symbol: payload.symbol,
            side: payload.side,
            price: new Prisma.Decimal(payload.price),
            qty: new Prisma.Decimal(payload.qty),
            status: "OPEN",
            mode: payload.mode as TradeMode,
            userId,
          },
        });

        await reserveOrderOnPlacement(
          {
            orderId: order.id,
            userId,
            symbol: payload.symbol,
            side: payload.side,
            qty: payload.qty,
            price: payload.price,
            mode: payload.mode as TradeMode,
          },
          tx,
        );

        const execution = await executeLimitOrderAgainstBook(
          {
            orderId: order.id,
            quoteFeeBps: payload.quoteFeeBps,
          },
          tx,
        );

        const reconciliation = await reconcileOrderExecution(order.id, tx);

        return {
          order: {
            id: execution.order.id.toString(),
            symbol: execution.order.symbol,
            side: execution.order.side,
            price: execution.order.price.toString(),
            qty: execution.order.qty.toString(),
            status: execution.order.status,
            mode: execution.order.mode,
            createdAt: execution.order.createdAt.toISOString(),
          },
          fills: execution.fills.length,
          remainingQty: execution.remainingQty,
          reconciliation,
        };
      });

      return res.status(201).json({ ok: true, ...result });
    } catch (error: any) {
      const message = error?.message ?? "Unable to place order";
      if (message.includes("insufficient") || message.includes("not balanced")) {
        return res.status(400).json({ error: message });
      }
      return res.status(400).json({ error: message });
    }
  },
);

router.post(
  "/:orderId/cancel",
  requireRecentMfa(),
  cancelLimiter,
  auditPrivilegedRequest("ORDER_CANCEL_REQUESTED", "ORDER", (req) => String(req.params.orderId)),
  async (req, res) => {
    try {
      const userId = req.auth!.userId;
      const orderId = BigInt(String(req.params.orderId));
      const order = await prisma.order.findUnique({ where: { id: orderId } });

      if (!order || order.userId !== userId) {
        return res.status(404).json({ error: "Order not found." });
      }

      if (!canCancel(order.status)) {
        return res.status(409).json({
          error: `Cannot cancel order in status ${order.status}.`,
        });
      }

      const remainingQty = await getOrderRemainingQty(order, prisma);
      if (remainingQty.lessThanOrEqualTo(0)) {
        return res.status(409).json({
          error: "Order has no remaining quantity to cancel.",
        });
      }

      const result = await prisma.$transaction(async (tx) => {
        const ledgerRelease = await releaseOrderOnCancel(
          {
            orderId: order.id,
            userId: order.userId,
            symbol: order.symbol,
            side: order.side,
            qty: remainingQty,
            price: order.price,
            mode: order.mode,
            reason: "CANCEL",
          },
          tx,
        );

        const cancelledOrder = await tx.order.update({
          where: { id: order.id },
          data: { status: ORDER_STATUS.CANCELLED },
        });

        return { order: cancelledOrder, ledgerRelease };
      });

      return res.json({
        ok: true,
        order: {
          id: result.order.id.toString(),
          symbol: result.order.symbol,
          side: result.order.side,
          price: result.order.price.toString(),
          qty: result.order.qty.toString(),
          status: result.order.status,
          mode: result.order.mode,
        },
        releasedQty: remainingQty.toString(),
      });
    } catch (error: any) {
      return res.status(400).json({ error: error?.message ?? "Unable to cancel order" });
    }
  },
);

router.get("/:orderId", async (req, res) => {
  try {
    const userId = req.auth!.userId;
    const orderId = BigInt(String(req.params.orderId));

    const order = await prisma.order.findUnique({
      where: { id: orderId },
      include: {
        buys: { orderBy: { createdAt: "desc" }, take: 50 },
        sells: { orderBy: { createdAt: "desc" }, take: 50 },
      },
    });

    if (!order || order.userId !== userId) {
      return res.status(404).json({ error: "Order not found." });
    }

    const trades = [...order.buys, ...order.sells]
      .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
      .map((t) => ({
        id: t.id.toString(),
        price: t.price.toString(),
        qty: t.qty.toString(),
        createdAt: t.createdAt.toISOString(),
      }));

    const remainingQty = await getOrderRemainingQty(order, prisma);

    return res.json({
      ok: true,
      order: {
        id: order.id.toString(),
        symbol: order.symbol,
        side: order.side,
        price: order.price.toString(),
        qty: order.qty.toString(),
        status: order.status,
        mode: order.mode,
        createdAt: order.createdAt.toISOString(),
        remainingQty: remainingQty.toString(),
      },
      trades,
    });
  } catch (error: any) {
    return res.status(500).json({ error: error?.message ?? "Unable to fetch order" });
  }
});

export default router;
""")
orders_path.parent.mkdir(parents=True, exist_ok=True)
orders_path.write_text(orders_ts)

app_text = app_path.read_text()
if 'import ordersRoutes from "./routes/orders";' not in app_text:
    if 'import tradeRoutes from "./routes/trade";' not in app_text:
        raise SystemExit("Could not find tradeRoutes import in app.ts")
    app_text = app_text.replace(
        'import tradeRoutes from "./routes/trade";',
        'import tradeRoutes from "./routes/trade"; import ordersRoutes from "./routes/orders";',
        1,
    )

mount_line = 'app.use("/api/orders", ordersRoutes);'
if mount_line not in app_text:
    anchor = 'for (const prefix of ["/api/v1/mandates", "/v1/mandates"]) { app.use(prefix, mandatesRoutes); }'
    if anchor not in app_text:
        raise SystemExit("Could not find mandates mount anchor in app.ts")
    app_text = app_text.replace(anchor, anchor + ' ' + mount_line, 1)

app_path.write_text(app_text)

test_ts = dedent("""import express from "express";
import request from "supertest";
import { Decimal } from "@prisma/client/runtime/library";
import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  prismaMock,
  executeLimitOrderAgainstBook,
  getOrderRemainingQty,
  reconcileOrderExecution,
  releaseOrderOnCancel,
  reserveOrderOnPlacement,
} = vi.hoisted(() => ({
  prismaMock: {
    order: {
      findMany: vi.fn(),
      findUnique: vi.fn(),
    },
    market: {
      findUnique: vi.fn(),
    },
    $transaction: vi.fn(),
  },
  executeLimitOrderAgainstBook: vi.fn(),
  getOrderRemainingQty: vi.fn(),
  reconcileOrderExecution: vi.fn(),
  releaseOrderOnCancel: vi.fn(),
  reserveOrderOnPlacement: vi.fn(),
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/ledger", () => ({
  executeLimitOrderAgainstBook,
  getOrderRemainingQty,
  reconcileOrderExecution,
  releaseOrderOnCancel,
  reserveOrderOnPlacement,
}));
vi.mock("../src/middleware/audit-privileged", () => ({
  auditPrivilegedRequest: () => (_req: any, _res: any, next: (err?: unknown) => void) => next(),
}));
vi.mock("../src/middleware/simple-rate-limit", () => ({
  simpleRateLimit: () => (_req: any, _res: any, next: (err?: unknown) => void) => next(),
}));
vi.mock("../src/middleware/require-auth", () => ({
  requireAuth: (req: any, res: any, next: (err?: unknown) => void) => {
    if (req.header("x-test-auth") !== "ok") {
      return res.status(401).json({ error: "Authentication required." });
    }
    req.auth = {
      userId: "user-1",
      sessionId: "session-1",
      roleCodes: ["USER"],
      mfaSatisfied: true,
      mfaMethod: "TOTP",
      mfaVerifiedAt: new Date(),
    };
    next();
  },
  requireRecentMfa: () => (_req: any, _res: any, next: (err?: unknown) => void) => next(),
  requireLiveModeEligible: () => (_req: any, _res: any, next: (err?: unknown) => void) => next(),
}));

import ordersRoutes from "../src/routes/orders";

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use("/api/orders", ordersRoutes);
  return app;
}

describe("orders routes", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns 401 without session auth", async () => {
    const app = buildApp();
    const response = await request(app).get("/api/orders");
    expect(response.status).toBe(401);
    expect(response.body).toEqual({ error: "Authentication required." });
  });

  it("lists only the authenticated user orders", async () => {
    const app = buildApp();

    prismaMock.order.findMany.mockResolvedValue([
      {
        id: 101n,
        symbol: "BTC-USD",
        side: "BUY",
        price: new Decimal("100"),
        qty: new Decimal("2"),
        status: "OPEN",
        mode: "PAPER",
        createdAt: new Date("2026-04-15T00:00:00.000Z"),
      },
    ]);

    const response = await request(app)
      .get("/api/orders?mode=paper&limit=25")
      .set("x-test-auth", "ok");

    expect(response.status).toBe(200);
    expect(prismaMock.order.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ userId: "user-1", mode: "PAPER" }),
        take: 25,
      }),
    );
    expect(response.body.ok).toBe(true);
    expect(response.body.orders).toHaveLength(1);
    expect(response.body.orders[0]).toMatchObject({
      id: "101",
      symbol: "BTC-USD",
      status: "OPEN",
      mode: "PAPER",
    });
  });

  it("rejects fetching another user order detail", async () => {
    const app = buildApp();

    prismaMock.order.findUnique.mockResolvedValue({
      id: 201n,
      userId: "someone-else",
      symbol: "BTC-USD",
      side: "BUY",
      price: new Decimal("100"),
      qty: new Decimal("2"),
      status: "OPEN",
      mode: "PAPER",
      createdAt: new Date("2026-04-15T00:00:00.000Z"),
      buys: [],
      sells: [],
    });

    const response = await request(app)
      .get("/api/orders/201")
      .set("x-test-auth", "ok");

    expect(response.status).toBe(404);
    expect(response.body).toEqual({ error: "Order not found." });
  });

  it("allows cancelling a PARTIALLY_FILLED order for the current user", async () => {
    const app = buildApp();
    const order = {
      id: 301n,
      userId: "user-1",
      symbol: "BTC-USD",
      side: "BUY",
      price: new Decimal("100"),
      qty: new Decimal("10"),
      status: "PARTIALLY_FILLED",
      mode: "PAPER",
      createdAt: new Date("2026-04-15T00:00:00.000Z"),
    };

    prismaMock.order.findUnique.mockResolvedValue(order);
    getOrderRemainingQty.mockResolvedValue(new Decimal("6"));
    releaseOrderOnCancel.mockResolvedValue({ ok: true });
    prismaMock.$transaction.mockImplementation(async (fn: any) =>
      fn({
        order: {
          update: vi.fn().mockResolvedValue({
            ...order,
            status: "CANCELLED",
          }),
        },
      }),
    );

    const response = await request(app)
      .post("/api/orders/301/cancel")
      .set("x-test-auth", "ok");

    expect(response.status).toBe(200);
    expect(releaseOrderOnCancel).toHaveBeenCalled();
    expect(response.body).toMatchObject({
      ok: true,
      releasedQty: "6",
    });
  });
});
""")
test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(test_ts)

print("Patched package.json, added orders.ts, mounted /api/orders only, and wrote apps/api/test/orders.routes.test.ts for Phase 2J.")
PY

echo "Resolved repo root: $ROOT"
echo "Phase 2J patch applied."
