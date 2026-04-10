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
