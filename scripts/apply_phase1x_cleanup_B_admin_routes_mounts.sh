#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

mkdir -p scripts

cat > apps/api/src/routes/admin.ts <<'TS'
import { Router } from "express";
import type { Request } from "express";
import { z } from "zod";

import { auditPrivilegedRequest } from "../middleware/audit-privileged";
import { requireAdminRecentMfa, requireAuth, requireRole } from "../middleware/require-auth";
import { bus } from "../infra/bus";
import { featureFlags } from "../infra/featureFlags";
import { riskLimits } from "../infra/riskLimits";
import { symbolControl, type TradingMode } from "../infra/symbolControl";

const router = Router();

const requireAdminRole = requireRole("admin", "auditor");
const requireAdminStepUp = requireAdminRecentMfa(["admin", "auditor"]);

router.use(requireAuth, requireAdminRole, requireAdminStepUp);

function normalizeRiskPayload(payload: {
  maxOrderQty?: string | number;
  maxOrderNotional?: string | number;
  maxOpenOrders?: number;
  reason?: string;
  updatedBy?: string;
}) {
  return {
    ...payload,
    maxOrderQty:
      payload.maxOrderQty === undefined ? undefined : String(payload.maxOrderQty),
    maxOrderNotional:
      payload.maxOrderNotional === undefined ? undefined : String(payload.maxOrderNotional),
  };
}

const setModeSchema = z.object({
  mode: z.enum(["OPEN", "HALT", "CANCEL_ONLY"]),
  reason: z.string().optional(),
  updatedBy: z.string().optional(),
});

const riskSchema = z.object({
  maxOrderQty: z.union([z.string(), z.number()]).optional(),
  maxOrderNotional: z.union([z.string(), z.number()]).optional(),
  maxOpenOrders: z.number().int().min(0).optional(),
  reason: z.string().optional(),
  updatedBy: z.string().optional(),
});

const flagsSchema = z.object({
  orderbookDefaultLevel: z.union([z.literal(2), z.literal(3)]).optional(),
  streamDefaultLevel: z.union([z.literal(2), z.literal(3)]).optional(),
  publicAllowL3: z.boolean().optional(),
  enableSSE: z.boolean().optional(),
  reason: z.string().optional(),
  updatedBy: z.string().optional(),
});

function symbolFromReq(req: Request): string | undefined {
  const symbol = String(req.params.symbol ?? "").toUpperCase().trim();
  return symbol || undefined;
}

router.get(
  "/symbols",
  auditPrivilegedRequest("ADMIN_SYMBOLS_LIST", "SYMBOL"),
  (_req, res) => {
    res.json({ ok: true, symbols: symbolControl.list() });
  },
);

router.get(
  "/symbols/:symbol",
  auditPrivilegedRequest("ADMIN_SYMBOL_GET", "SYMBOL", (req) => symbolFromReq(req)),
  (req, res) => {
    const symbol = symbolFromReq(req)!;
    res.json({ ok: true, symbol, control: symbolControl.get(symbol) });
  },
);

router.post(
  "/symbols/:symbol",
  auditPrivilegedRequest("ADMIN_SYMBOL_SET", "SYMBOL", (req) => symbolFromReq(req)),
  (req, res) => {
    const symbol = symbolFromReq(req)!;
    const payload = setModeSchema.parse(req.body);
    const control = symbolControl.set(symbol, {
      mode: payload.mode as TradingMode,
      reason: payload.reason,
      updatedBy: payload.updatedBy ?? req.auth?.userId,
    });
    bus.emit("symbolMode", { symbol });
    res.json({ ok: true, symbol, control });
  },
);

router.post(
  "/symbols/:symbol/clear",
  auditPrivilegedRequest("ADMIN_SYMBOL_CLEAR", "SYMBOL", (req) => symbolFromReq(req)),
  (req, res) => {
    const symbol = symbolFromReq(req)!;
    symbolControl.clear(symbol);
    bus.emit("symbolMode", { symbol });
    res.json({ ok: true, symbol, control: symbolControl.get(symbol) });
  },
);

router.get(
  "/risk/defaults",
  auditPrivilegedRequest("ADMIN_RISK_DEFAULTS_GET", "RISK_LIMIT"),
  (_req, res) => {
    res.json({ ok: true, defaults: riskLimits.getDefaults() });
  },
);

router.post(
  "/risk/defaults",
  auditPrivilegedRequest("ADMIN_RISK_DEFAULTS_SET", "RISK_LIMIT"),
  (req, res) => {
    const payload = riskSchema.parse(req.body);
    const defaults = riskLimits.setDefaults(normalizeRiskPayload(payload));
    bus.emit("riskLimits", { symbol: "*" });
    res.json({ ok: true, defaults });
  },
);

router.get(
  "/risk",
  auditPrivilegedRequest("ADMIN_RISK_OVERRIDES_LIST", "RISK_LIMIT"),
  (_req, res) => {
    res.json({ ok: true, overrides: riskLimits.listOverrides() });
  },
);

router.get(
  "/risk/:symbol",
  auditPrivilegedRequest("ADMIN_RISK_GET", "RISK_LIMIT", (req) => symbolFromReq(req)),
  (req, res) => {
    const symbol = symbolFromReq(req)!;
    res.json({ ok: true, symbol, limits: riskLimits.get(symbol) });
  },
);

router.post(
  "/risk/:symbol",
  auditPrivilegedRequest("ADMIN_RISK_SET", "RISK_LIMIT", (req) => symbolFromReq(req)),
  (req, res) => {
    const symbol = symbolFromReq(req)!;
    const payload = riskSchema.parse(req.body);
    const limits = riskLimits.set(symbol, normalizeRiskPayload(payload));
    bus.emit("riskLimits", { symbol });
    res.json({ ok: true, symbol, limits });
  },
);

router.post(
  "/risk/:symbol/clear",
  auditPrivilegedRequest("ADMIN_RISK_CLEAR", "RISK_LIMIT", (req) => symbolFromReq(req)),
  (req, res) => {
    const symbol = symbolFromReq(req)!;
    riskLimits.clear(symbol);
    bus.emit("riskLimits", { symbol });
    res.json({ ok: true, symbol, limits: riskLimits.get(symbol) });
  },
);

router.get(
  "/flags/defaults",
  auditPrivilegedRequest("ADMIN_FLAGS_DEFAULTS_GET", "FEATURE_FLAG"),
  (_req, res) => {
    res.json({ ok: true, defaults: featureFlags.getDefaults() });
  },
);

router.post(
  "/flags/defaults",
  auditPrivilegedRequest("ADMIN_FLAGS_DEFAULTS_SET", "FEATURE_FLAG"),
  (req, res) => {
    const payload = flagsSchema.parse(req.body);
    const defaults = featureFlags.setDefaults(payload);
    bus.emit("flags", { symbol: "*" });
    res.json({ ok: true, defaults });
  },
);

router.get(
  "/flags",
  auditPrivilegedRequest("ADMIN_FLAGS_OVERRIDES_LIST", "FEATURE_FLAG"),
  (_req, res) => {
    res.json({ ok: true, overrides: featureFlags.listOverrides() });
  },
);

router.get(
  "/flags/:symbol",
  auditPrivilegedRequest("ADMIN_FLAGS_GET", "FEATURE_FLAG", (req) => symbolFromReq(req)),
  (req, res) => {
    const symbol = symbolFromReq(req)!;
    res.json({ ok: true, symbol, flags: featureFlags.get(symbol) });
  },
);

router.post(
  "/flags/:symbol",
  auditPrivilegedRequest("ADMIN_FLAGS_SET", "FEATURE_FLAG", (req) => symbolFromReq(req)),
  (req, res) => {
    const symbol = symbolFromReq(req)!;
    const payload = flagsSchema.parse(req.body);
    const flags = featureFlags.set(symbol, payload);
    bus.emit("flags", { symbol });
    res.json({ ok: true, symbol, flags });
  },
);

router.post(
  "/flags/:symbol/clear",
  auditPrivilegedRequest("ADMIN_FLAGS_CLEAR", "FEATURE_FLAG", (req) => symbolFromReq(req)),
  (req, res) => {
    const symbol = symbolFromReq(req)!;
    featureFlags.clear(symbol);
    bus.emit("flags", { symbol });
    res.json({ ok: true, symbol, flags: featureFlags.get(symbol) });
  },
);

export default router;
TS

rm -f apps/api/src/routes/flags.ts

cat > apps/api/src/app.ts <<'TS'
import crypto from "crypto";
import cors from "cors";
import express from "express";
import helmet from "helmet";

import advisorRoutes from "./modules/advisor/advisor.routes";
import authRoutes from "./modules/auth/auth.routes";
import consentsRoutes from "./modules/consents/consents.routes";
import invitationsRoutes from "./modules/invitations/invitations.routes";
import kycRoutes from "./modules/kyc/kyc.routes";
import onboardingRoutes from "./modules/onboarding/onboarding.routes";
import referralsRoutes from "./modules/referrals/referrals.routes";
import uploadsRoutes from "./modules/uploads/uploads.routes";
import verificationRoutes from "./modules/verification/verification.routes";
import adminRoutes from "./routes/admin";
import agenticRoutes from "./routes/agentic";
import agentsRoutes from "./routes/agents";
import mandatesRoutes from "./routes/mandates";
import marketRoutes from "./routes/market";
import streamRoutes from "./routes/stream";
import tradeRoutes from "./routes/trade";

const app = express();

const corsOrigins = (process.env.APP_CORS_ORIGINS ?? "http://localhost:3000")
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);

const apiRouters = [
  onboardingRoutes,
  advisorRoutes,
  consentsRoutes,
  uploadsRoutes,
  invitationsRoutes,
  authRoutes,
  verificationRoutes,
  kycRoutes,
  referralsRoutes,
];

const trustProxy = process.env.TRUST_PROXY;
app.set("trust proxy", trustProxy === "1" || trustProxy === "true");
app.disable("x-powered-by");
app.set("json replacer", (_key: string, value: unknown) => {
  return typeof value === "bigint" ? value.toString() : value;
});

app.use((req, res, next) => {
  const requestId = req.header("x-request-id")?.trim() || crypto.randomUUID();
  (req as any).requestId = requestId;
  res.setHeader("x-request-id", requestId);
  next();
});

app.use(
  helmet({
    contentSecurityPolicy: false,
    crossOriginEmbedderPolicy: false,
  }),
);

app.use((_, res, next) => {
  res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  next();
});

app.use(
  cors({
    origin(origin, callback) {
      if (!origin || corsOrigins.includes(origin)) {
        return callback(null, true);
      }
      return callback(new Error("Origin not allowed by CORS"));
    },
    credentials: true,
  }),
);

app.use(express.json({ limit: "100kb" }));
app.use(express.urlencoded({ extended: false, limit: "50kb" }));

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

app.get("/ready", (_req, res) => {
  res.json({ ok: true });
});

for (const prefix of ["/api", "/backend-api"]) {
  for (const router of apiRouters) {
    app.use(prefix, router);
  }
}

for (const prefix of ["/api/admin", "/admin"]) {
  app.use(prefix, adminRoutes);
}

for (const prefix of ["/api/v1/agents", "/v1/agents"]) {
  app.use(prefix, agentsRoutes);
}

for (const prefix of ["/api/v1/mandates", "/v1/mandates"]) {
  app.use(prefix, mandatesRoutes);
}

for (const prefix of ["/api/v1/ui", "/v1/ui"]) {
  app.use(prefix, agenticRoutes);
}

for (const prefix of ["", "/v1/market", "/api/v1/market"]) {
  app.use(prefix, marketRoutes);
}

for (const prefix of ["", "/v1/trade", "/api/v1/trade"]) {
  app.use(prefix, tradeRoutes);
}

for (const prefix of ["", "/v1/stream", "/api/v1/stream"]) {
  app.use(prefix, streamRoutes);
}

app.use((req, res) => {
  const requestId = (req as any).requestId;
  res.status(404).json({
    error: {
      code: "NOT_FOUND",
      message: "Route not found.",
    },
    requestId,
  });
});

app.use((err: any, req: express.Request, res: express.Response, _next: express.NextFunction) => {
  const status = err.statusCode || 500;
  const requestId = (req as any).requestId;

  if (status >= 500) {
    console.error("[api-error]", {
      requestId,
      status,
      code: err.code || "INTERNAL_ERROR",
      message: err.message,
      path: req.originalUrl,
      method: req.method,
    });
  }

  res.status(status).json({
    error: {
      code: err.code || "INTERNAL_ERROR",
      message: err.message || "Internal server error.",
      fieldErrors: err.fieldErrors,
      retryable: err.retryable,
    },
    requestId,
  });
});

export default app;
TS

echo "Patched apps/api/src/routes/admin.ts, removed apps/api/src/routes/flags.ts, and mounted missing route groups in apps/api/src/app.ts"
echo "Cleanup B patch applied."
