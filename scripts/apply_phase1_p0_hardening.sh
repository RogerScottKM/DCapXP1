#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

if [[ ! -f "docker-compose.yml" ]] || [[ ! -d "apps/api/src" ]]; then
  echo "Run this from the DCapXP1 repository root, or pass the repo path as the first argument."
  exit 1
fi

backup_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    cp -p "$file" "$file.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

mkdir -p apps/api/src/middleware
mkdir -p apps/api/src/lib
mkdir -p apps/api/src/modules/auth
mkdir -p apps/api/src/modules/verification
mkdir -p apps/api/src/modules/notifications

for file in \
  docker-compose.yml \
  docker-compose.prod.yml \
  apps/api/src/app.ts \
  apps/api/src/server.ts \
  apps/api/src/lib/auth.ts \
  apps/api/src/middleware/auth.ts \
  apps/api/src/middleware/require-auth.ts \
  apps/api/src/middleware/simple-rate-limit.ts \
  apps/api/src/modules/auth/auth.routes.ts \
  apps/api/src/modules/auth/auth.service.ts \
  apps/api/src/modules/verification/verification.routes.ts \
  apps/api/src/modules/verification/verification.service.ts \
  apps/api/src/lib/session-auth.ts \
  apps/api/src/modules/notifications/notifications.config.ts
  do
  backup_file "$file"
done

cat > docker-compose.yml <<'YAML'
services:
  pg:
    image: postgres:16
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-dcapx}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-dcapx_local_only_change_me}
      POSTGRES_DB: ${POSTGRES_DB:-dcapx}
    volumes:
      - dcapx_pg:/var/lib/postgresql/data
    networks:
      - data
      - devhost
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-dcapx} -d ${POSTGRES_DB:-dcapx}"]
      interval: 5s
      timeout: 5s
      retries: 20
    ports:
      - "127.0.0.1:5445:5432"

  redis:
    image: redis:7
    volumes:
      - dcapx_redis:/data
    networks:
      - data
    healthcheck:
      test: ["CMD-SHELL", "redis-cli ping | grep PONG"]
      interval: 5s
      timeout: 3s
      retries: 20

  api:
    build:
      context: .
      dockerfile: apps/api/Dockerfile
    environment:
      NODE_ENV: ${NODE_ENV:-development}
      API_PORT: "4010"
      DATABASE_URL: ${DATABASE_URL:-postgresql://dcapx:dcapx_local_only_change_me@pg:5432/dcapx?schema=public}
      REDIS_URL: ${REDIS_URL:-redis://redis:6379}
      ADMIN_KEY: ${ADMIN_KEY:-local-dev-admin-key-change-me}
      JWT_SECRET: ${JWT_SECRET:-local-dev-jwt-secret-change-me}
      OTP_HMAC_SECRET: ${OTP_HMAC_SECRET:-local-dev-otp-secret-change-me}
      APP_BASE_URL: ${APP_BASE_URL:-http://localhost:3002}
      APP_CORS_ORIGINS: ${APP_CORS_ORIGINS:-http://localhost:3002,http://localhost:53002}
      EMAIL_PROVIDER: ${EMAIL_PROVIDER:-console}
      EMAIL_FROM: ${EMAIL_FROM:-DCapX <no-reply@dcapitalx.local>}
    depends_on:
      pg:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - app
      - data
    ports:
      - "127.0.0.1:4010:4010"
    working_dir: /app/apps/api
    command: ["sh", "-lc", "pnpm prisma migrate deploy && pnpm start"]
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:4010/health || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 20s
    stop_grace_period: 30s
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true

  web:
    build:
      context: .
      dockerfile: apps/web/Dockerfile
    environment:
      NODE_ENV: "production"
      HOSTNAME: "0.0.0.0"
      API_INTERNAL_URL: "http://api:4010"
    depends_on:
      api:
        condition: service_healthy
    networks:
      - public
      - app
    ports:
      - "127.0.0.1:3000:3000"
    healthcheck:
      test: ["CMD-SHELL", "node -e \"fetch('http://127.0.0.1:3000/').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\""]
      interval: 10s
      timeout: 3s
      retries: 10
      start_period: 30s
    stop_grace_period: 30s
    restart: unless-stopped

volumes:
  dcapx_pg:
  dcapx_redis:

networks:
  public: {}
  app: {}
  data:
    internal: true
  devhost: {}
YAML

cat > docker-compose.prod.yml <<'YAML'
services:
  api:
    build:
      context: .
      dockerfile: apps/api/Dockerfile
    container_name: dcapx-api
    command: ["bash", "-lc", "pnpm prisma generate && pnpm prisma migrate deploy && node dist/server.js"]
    environment:
      NODE_ENV: "production"
      PORT: "4010"
      DATABASE_URL: ${DATABASE_URL?DATABASE_URL is required}
      REDIS_URL: ${REDIS_URL:-redis://redis:6379}
      ADMIN_KEY: ${ADMIN_KEY?ADMIN_KEY is required}
      JWT_SECRET: ${JWT_SECRET?JWT_SECRET is required}
      OTP_HMAC_SECRET: ${OTP_HMAC_SECRET?OTP_HMAC_SECRET is required}
      APP_BASE_URL: ${APP_BASE_URL?APP_BASE_URL is required}
      APP_CORS_ORIGINS: ${APP_CORS_ORIGINS?APP_CORS_ORIGINS is required}
      EMAIL_PROVIDER: ${EMAIL_PROVIDER:-resend}
      EMAIL_FROM: ${EMAIL_FROM?EMAIL_FROM is required}
      RESEND_API_KEY: ${RESEND_API_KEY:-}
      TRUST_PROXY: ${TRUST_PROXY:-1}
    depends_on:
      pg:
        condition: service_healthy
      redis:
        condition: service_healthy
    ports:
      - "127.0.0.1:4010:4010"
    restart: unless-stopped
    stop_grace_period: 30s
    healthcheck:
      test: ["CMD-SHELL", "node -e \"fetch('http://127.0.0.1:4010/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\""]
      interval: 10s
      timeout: 3s
      retries: 10
      start_period: 30s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"
    security_opt:
      - no-new-privileges:true

  web:
    build:
      context: .
      dockerfile: apps/web/Dockerfile
    container_name: dcapx-web
    environment:
      API_INTERNAL_URL: "http://api:4010"
      NODE_ENV: "production"
      HOSTNAME: "0.0.0.0"
      PORT: "3000"
    depends_on:
      - api
    ports:
      - "127.0.0.1:3000:3000"
    restart: unless-stopped
    stop_grace_period: 30s
    healthcheck:
      test: ["CMD-SHELL", "node -e \"fetch('http://127.0.0.1:3000/').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\""]
      interval: 10s
      timeout: 3s
      retries: 10
      start_period: 30s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"

  pg:
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"

  redis:
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"
YAML

cat > apps/api/src/middleware/simple-rate-limit.ts <<'TS'
import type { NextFunction, Request, Response } from "express";

type RateLimitOptions = {
  keyPrefix: string;
  windowMs: number;
  max: number;
};

type Bucket = {
  count: number;
  resetAt: number;
};

const buckets = new Map<string, Bucket>();

function getClientIp(req: Request): string {
  const forwarded = req.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.trim()) {
    return forwarded.split(",")[0].trim();
  }
  return req.socket.remoteAddress ?? "unknown";
}

export function simpleRateLimit(options: RateLimitOptions) {
  return (req: Request, res: Response, next: NextFunction) => {
    const now = Date.now();
    const key = `${options.keyPrefix}:${getClientIp(req)}`;
    const current = buckets.get(key);

    const bucket: Bucket =
      !current || current.resetAt <= now
        ? { count: 0, resetAt: now + options.windowMs }
        : current;

    bucket.count += 1;
    buckets.set(key, bucket);

    res.setHeader("X-RateLimit-Limit", String(options.max));
    res.setHeader("X-RateLimit-Remaining", String(Math.max(0, options.max - bucket.count)));
    res.setHeader("X-RateLimit-Reset", String(Math.ceil(bucket.resetAt / 1000)));

    if (bucket.count > options.max) {
      return res.status(429).json({
        error: {
          code: "RATE_LIMITED",
          message: "Too many requests. Please try again later.",
        },
      });
    }

    return next();
  };
}
TS

cat > apps/api/src/app.ts <<'TS'
import crypto from "crypto";
import express from "express";
import cors from "cors";
import kycRoutes from "./modules/kyc/kyc.routes";
import authRoutes from "./modules/auth/auth.routes";
import onboardingRoutes from "./modules/onboarding/onboarding.routes";
import advisorRoutes from "./modules/advisor/advisor.routes";
import invitationsRoutes from "./modules/invitations/invitations.routes";
import uploadsRoutes from "./modules/uploads/uploads.routes";
import consentsRoutes from "./modules/consents/consents.routes";
import referralsRoutes from "./modules/referrals/referrals.routes";
import marketRoutes from "./routes/market";
import tradeRoutes from "./routes/trade";
import streamRoutes from "./routes/stream";
import verificationRoutes from "./modules/verification/verification.routes";

const app = express();

const corsOrigins = (process.env.APP_CORS_ORIGINS ?? "http://localhost:3002,http://localhost:53002")
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

app.set("trust proxy", process.env.TRUST_PROXY === "1");

app.set("json replacer", (_key: string, value: unknown) => {
  return typeof value === "bigint" ? value.toString() : value;
});

app.use((req, res, next) => {
  const requestId = req.header("x-request-id")?.trim() || crypto.randomUUID();
  (req as any).requestId = requestId;
  res.setHeader("x-request-id", requestId);
  next();
});

app.use((_, res, next) => {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=() ");
  next();
});

app.use(
  cors({
    origin: corsOrigins,
    credentials: true,
  })
);

app.use(express.json({ limit: "100kb" }));
app.use(express.urlencoded({ extended: false, limit: "50kb" }));

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

app.get("/ready", (_req, res) => {
  res.json({ ok: true });
});

for (const router of apiRouters) {
  app.use("/api", router);
  app.use("/backend-api", router);
}

app.use(marketRoutes);
app.use(tradeRoutes);
app.use(streamRoutes);
app.use("/v1/market", marketRoutes);
app.use("/api/v1/market", marketRoutes);
app.use("/v1/stream", streamRoutes);
app.use("/api/v1/stream", streamRoutes);

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

cat > apps/api/src/server.ts <<'TS'
import "dotenv/config";
import type { Server } from "http";
import app from "./app";
import { prisma } from "./lib/prisma";

const PORT = Number(process.env.API_PORT ?? process.env.PORT ?? 4010);
const IS_PRODUCTION = process.env.NODE_ENV === "production";

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

let server: Server | null = null;
let shuttingDown = false;

async function shutdown(signal: string): Promise<void> {
  if (shuttingDown) {
    return;
  }

  shuttingDown = true;
  console.log(`[server] received ${signal}, shutting down`);

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
  validateEnv();

  server = app.listen(PORT, () => {
    console.log(`api listening on ${PORT}`);
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
TS

cat > apps/api/src/lib/auth.ts <<'TS'
import type { NextFunction, Response } from "express";

function getJwtSecret(): Uint8Array {
  const value = process.env.JWT_SECRET?.trim();
  if (!value) {
    throw new Error("JWT_SECRET is required");
  }
  return new TextEncoder().encode(value);
}

const JWT_ISSUER = process.env.JWT_ISSUER ?? "dcapx-api";
const JWT_AUDIENCE = process.env.JWT_AUDIENCE ?? "dcapx-clients";

export type AuthPayload = {
  sub: string;
  email?: string;
  tenantId?: string;
  roles?: string[];
  [k: string]: any;
};

export async function requireAuth(req: any, res: Response, next: NextFunction) {
  const h = req.headers.authorization || "";
  const token = typeof h === "string" && h.startsWith("Bearer ") ? h.slice(7) : null;

  if (!token) {
    return res.status(401).json({ ok: false, error: "Unauthorized" });
  }

  try {
    const { jwtVerify } = await import("jose");
    const { payload } = await jwtVerify(token, getJwtSecret(), {
      issuer: JWT_ISSUER,
      audience: JWT_AUDIENCE,
      algorithms: ["HS256"],
    });

    req.auth = payload as AuthPayload;
    req.userId = String(payload.sub);

    return next();
  } catch {
    return res.status(401).json({ ok: false, error: "BadToken" });
  }
}

export async function signToken(userId: string, claims: Record<string, any> = {}) {
  const { SignJWT } = await import("jose");

  return await new SignJWT(claims)
    .setProtectedHeader({ alg: "HS256" })
    .setIssuer(JWT_ISSUER)
    .setAudience(JWT_AUDIENCE)
    .setSubject(userId)
    .setIssuedAt()
    .setExpirationTime("12h")
    .sign(getJwtSecret());
}
TS

cat > apps/api/src/middleware/auth.ts <<'TS'
import type { NextFunction, Request, Response } from "express";
import { ApiError } from "../lib/errors/api-error";
import { authService } from "../modules/auth/auth.service";

export type AuthedRequest = Request & {
  auth?: { userId: string; sessionId?: string };
  user?: { id: string; username: string };
};

export async function requireUser(req: AuthedRequest, _res: Response, next: NextFunction) {
  try {
    const auth = await authService.resolveAuthFromRequest(req);

    if (!auth) {
      throw new ApiError({
        statusCode: 401,
        code: "UNAUTHENTICATED",
        message: "Authentication required.",
      });
    }

    req.auth = auth;
    req.user = { id: auth.userId, username: auth.userId };
    next();
  } catch (error) {
    next(error);
  }
}

export function requireMfa(_req: AuthedRequest, _res: Response, next: NextFunction) {
  next(
    new ApiError({
      statusCode: 501,
      code: "MFA_NOT_IMPLEMENTED",
      message:
        "Legacy development MFA bypass has been disabled. Wire this route to real TOTP/session step-up before enabling it in production.",
    })
  );
}

export function authFromJwt(_req: Request, _res: Response, next: NextFunction) {
  next(
    new ApiError({
      statusCode: 501,
      code: "LEGACY_AUTH_DISABLED",
      message:
        "Legacy auth middleware is disabled. Use the canonical session-based require-auth middleware instead.",
    })
  );
}
TS

cat > apps/api/src/middleware/require-auth.ts <<'TS'
import type { Request, Response, NextFunction } from "express";
import { ApiError } from "../lib/errors/api-error";
import { authService } from "../modules/auth/auth.service";

declare global {
  namespace Express {
    interface Request {
      auth?: { userId: string; sessionId?: string };
    }
  }
}

export async function requireAuth(req: Request, _res: Response, next: NextFunction) {
  try {
    const auth = await authService.resolveAuthFromRequest(req);

    if (!auth) {
      throw new ApiError({
        statusCode: 401,
        code: "UNAUTHENTICATED",
        message: "Authentication required.",
      });
    }

    req.auth = auth;
    next();
  } catch (error) {
    next(error);
  }
}
TS

cat > apps/api/src/modules/auth/auth.routes.ts <<'TS'
import { Router } from "express";
import {
  getSession,
  login,
  logout,
  register,
  requestPasswordReset,
  resetPassword,
  sendOtp,
  verifyOtp,
} from "./auth.controller";
import { requireAuth } from "../../middleware/require-auth";
import { simpleRateLimit } from "../../middleware/simple-rate-limit";

const router = Router();

const registerLimiter = simpleRateLimit({ keyPrefix: "auth:register", windowMs: 10 * 60 * 1000, max: 10 });
const loginLimiter = simpleRateLimit({ keyPrefix: "auth:login", windowMs: 10 * 60 * 1000, max: 20 });
const passwordLimiter = simpleRateLimit({ keyPrefix: "auth:password", windowMs: 10 * 60 * 1000, max: 10 });
const otpLimiter = simpleRateLimit({ keyPrefix: "auth:otp", windowMs: 10 * 60 * 1000, max: 10 });

router.post("/auth/register", registerLimiter, register);
router.post("/auth/login", loginLimiter, login);
router.get("/auth/session", getSession);
router.post("/auth/logout", requireAuth, logout);

router.post("/auth/request-password-reset", passwordLimiter, requestPasswordReset);
router.post("/auth/reset-password", passwordLimiter, resetPassword);

router.post("/auth/send-otp", requireAuth, otpLimiter, sendOtp);
router.post("/auth/verify-otp", requireAuth, otpLimiter, verifyOtp);

export default router;
TS

cat > apps/api/src/modules/auth/auth.service.ts <<'TS'
import argon2 from "argon2";
import crypto from "crypto";
import type { Request, Response } from "express";
import { prisma } from "../../lib/prisma";
import { withTx } from "../../lib/service/tx";
import { writeAuditEvent } from "../../lib/service/audit";
import { parseDto } from "../../lib/service/zod";
import { registerDto } from "./auth.dto";
import { mapRegisterDtoToUserCreate } from "./auth.mappers";
import { ApiError } from "../../lib/errors/api-error";
import {
  buildSessionCookieValue,
  clearSessionCookie,
  createSessionSecret,
  getCookieFromRequest,
  getSessionExpiryDate,
  hashSessionSecret,
  parseSessionCookieValue,
  SESSION_COOKIE_NAME,
  setSessionCookie,
  verifySessionSecret,
} from "../../lib/session-auth";
import { verificationService } from "../verification/verification.service";

export async function registerUser(input: unknown) {
  const dto = parseDto(registerDto, input);
  const passwordHash = await argon2.hash(crypto.randomBytes(32).toString("hex"));

  return withTx(prisma, async (tx) => {
    const user = await tx.user.create({
      data: mapRegisterDtoToUserCreate(dto, passwordHash),
      include: { profile: true },
    });

    await writeAuditEvent(tx, {
      actorType: "USER",
      actorId: user.id,
      subjectType: "USER",
      subjectId: user.id,
      action: "USER_REGISTERED",
      resourceType: "User",
      resourceId: user.id,
      metadata: { email: user.email, username: user.username },
    });

    return user;
  });
}

type LoginRequestBody = {
  identifier?: string;
  password?: string;
};

type RequestPasswordResetBody = {
  email?: string;
};

type ResetPasswordBody = {
  token?: string;
  newPassword?: string;
};

type SendOtpBody = {
  channel?: "EMAIL" | "SMS";
};

type VerifyOtpBody = {
  channel?: "EMAIL" | "SMS";
  code?: string;
};

class AuthService {
  async login(req: Request, res: Response, body: LoginRequestBody) {
    const identifier = body?.identifier?.trim();
    const password = body?.password;

    if (!identifier || !password) {
      throw new ApiError({
        statusCode: 400,
        code: "LOGIN_INVALID_INPUT",
        message: "Identifier and password are required.",
        fieldErrors: {
          ...(identifier ? {} : { identifier: "Required" }),
          ...(password ? {} : { password: "Required" }),
        },
      });
    }

    const user = await prisma.user.findFirst({
      where: {
        OR: [{ email: identifier.toLowerCase() }, { username: identifier }],
      },
      include: {
        profile: true,
        roles: true,
      },
    });

    if (!user) {
      throw new ApiError({
        statusCode: 401,
        code: "LOGIN_INVALID_CREDENTIALS",
        message: "Invalid credentials.",
      });
    }

    if (user.status === "SUSPENDED" || user.status === "CLOSED") {
      throw new ApiError({
        statusCode: 403,
        code: "ACCOUNT_UNAVAILABLE",
        message: "This account is not available for sign-in.",
      });
    }

    const passwordOk = await argon2.verify(user.passwordHash, password);
    if (!passwordOk) {
      throw new ApiError({
        statusCode: 401,
        code: "LOGIN_INVALID_CREDENTIALS",
        message: "Invalid credentials.",
      });
    }

    const secret = createSessionSecret();
    const refreshTokenHash = await hashSessionSecret(secret);
    const expiresAt = getSessionExpiryDate();

    const session = await prisma.session.create({
      data: {
        userId: user.id,
        refreshTokenHash,
        expiresAt,
        ipAddress: this.getRequestIp(req),
        userAgent: req.headers["user-agent"]?.toString() ?? null,
      },
    });

    const cookieValue = buildSessionCookieValue(session.id, secret);
    setSessionCookie(res, cookieValue, expiresAt);

    return {
      ok: true,
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
        status: user.status,
        profile: user.profile
          ? {
              firstName: user.profile.firstName,
              lastName: user.profile.lastName,
              country: user.profile.country,
            }
          : null,
      },
      session: {
        id: session.id,
        expiresAtUtc: session.expiresAt.toISOString(),
      },
    };
  }

  async getSession(req: Request) {
    const auth = await this.resolveAuthFromRequest(req);

    if (!auth) {
      throw new ApiError({
        statusCode: 401,
        code: "UNAUTHENTICATED",
        message: "Authentication required.",
      });
    }

    const user = await prisma.user.findUnique({
      where: { id: auth.userId },
      include: { profile: true, roles: true },
    });

    if (!user) {
      throw new ApiError({
        statusCode: 401,
        code: "UNAUTHENTICATED",
        message: "Authentication required.",
      });
    }

    return {
      authenticated: true,
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
        status: user.status,
        profile: user.profile
          ? {
              firstName: user.profile.firstName,
              lastName: user.profile.lastName,
              country: user.profile.country,
              roles: user.roles.map((role) => ({
                roleCode: role.roleCode,
                scopeType: role.scopeType,
                scopeId: role.scopeId,
              })),
            }
          : null,
      },
      session: {
        id: auth.sessionId,
      },
    };
  }

  async logout(req: Request, res: Response) {
    const parsed = parseSessionCookieValue(getCookieFromRequest(req, SESSION_COOKIE_NAME));

    if (parsed?.sessionId) {
      await prisma.session.updateMany({
        where: {
          id: parsed.sessionId,
          revokedAt: null,
        },
        data: {
          revokedAt: new Date(),
        },
      });
    }

    clearSessionCookie(res);
    return { ok: true };
  }

  async requestPasswordReset(body: RequestPasswordResetBody) {
    const email = body?.email?.trim().toLowerCase();

    if (!email) {
      throw new ApiError({
        statusCode: 400,
        code: "PASSWORD_RESET_EMAIL_REQUIRED",
        message: "Email is required.",
      });
    }

    return verificationService.requestPasswordReset(email);
  }

  async resetPassword(body: ResetPasswordBody) {
    const token = body?.token?.trim();
    const newPassword = body?.newPassword;

    if (!token || !newPassword) {
      throw new ApiError({
        statusCode: 400,
        code: "PASSWORD_RESET_INVALID_INPUT",
        message: "Token and new password are required.",
      });
    }

    if (newPassword.length < 10) {
      throw new ApiError({
        statusCode: 400,
        code: "PASSWORD_TOO_SHORT",
        message: "Password must be at least 10 characters long.",
      });
    }

    return verificationService.resetPassword(token, newPassword);
  }

  async sendOtp(userId: string, body: SendOtpBody) {
    const channel = body?.channel || "EMAIL";
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        phone: true,
        emailVerifiedAt: true,
        phoneVerifiedAt: true,
      },
    });

    if (!user) {
      throw new ApiError({
        statusCode: 404,
        code: "USER_NOT_FOUND",
        message: "User not found.",
      });
    }

    const destination = channel === "EMAIL" ? user.email : user.phone;
    if (!destination) {
      throw new ApiError({
        statusCode: 400,
        code: "OTP_DESTINATION_MISSING",
        message:
          channel === "EMAIL"
            ? "No email is available for this account."
            : "No phone number is available for this account.",
      });
    }

    const now = new Date();
    await prisma.verificationCode.updateMany({
      where: {
        userId,
        channel,
        purpose: "CONTACT_VERIFICATION",
        consumedAt: null,
        expiresAt: { gt: now },
      },
      data: { consumedAt: now },
    });

    const code = this.generateOtpCode();
    const codeHash = this.hashVerificationCode(code);
    const expiresAt = new Date(Date.now() + 1000 * 60 * 10);

    await prisma.verificationCode.create({
      data: {
        userId,
        channel,
        purpose: "CONTACT_VERIFICATION",
        destination,
        codeHash,
        expiresAt,
      },
    });

    return {
      ok: true,
      message:
        channel === "EMAIL"
          ? "A verification code has been sent to your email."
          : "A verification code has been sent to your phone.",
      channel,
      destinationMasked: this.maskDestination(destination, channel),
      expiresAtUtc: expiresAt.toISOString(),
      ...(process.env.NODE_ENV !== "production" ? { devOtpCode: code } : {}),
    };
  }

  async verifyOtp(userId: string, body: VerifyOtpBody) {
    const channel = body?.channel || "EMAIL";
    const code = body?.code?.trim();

    if (!code) {
      throw new ApiError({
        statusCode: 400,
        code: "OTP_CODE_REQUIRED",
        message: "Verification code is required.",
      });
    }

    const record = await prisma.verificationCode.findFirst({
      where: {
        userId,
        channel,
        purpose: "CONTACT_VERIFICATION",
        consumedAt: null,
        expiresAt: { gt: new Date() },
      },
      orderBy: { createdAt: "desc" },
    });

    if (!record) {
      throw new ApiError({
        statusCode: 400,
        code: "OTP_INVALID",
        message: "This verification code is invalid or has expired.",
      });
    }

    const codeHash = this.hashVerificationCode(code);
    if (codeHash !== record.codeHash) {
      throw new ApiError({
        statusCode: 400,
        code: "OTP_INVALID",
        message: "This verification code is invalid or has expired.",
      });
    }

    const now = new Date();
    const [updatedUser] = await prisma.$transaction([
      prisma.user.update({
        where: { id: userId },
        data: channel === "EMAIL" ? { emailVerifiedAt: now } : { phoneVerifiedAt: now },
        select: { emailVerifiedAt: true, phoneVerifiedAt: true },
      }),
      prisma.verificationCode.update({
        where: { id: record.id },
        data: { consumedAt: now },
      }),
    ]);

    return {
      ok: true,
      message: channel === "EMAIL" ? "Your email has been verified." : "Your phone number has been verified.",
      emailVerifiedAtUtc: updatedUser.emailVerifiedAt?.toISOString() ?? null,
      phoneVerifiedAtUtc: updatedUser.phoneVerifiedAt?.toISOString() ?? null,
    };
  }

  async resolveAuthFromRequest(req: Request): Promise<{ userId: string; sessionId: string } | null> {
    const rawCookie = getCookieFromRequest(req, SESSION_COOKIE_NAME);
    const parsed = parseSessionCookieValue(rawCookie);
    if (!parsed) return null;

    const session = await prisma.session.findUnique({
      where: { id: parsed.sessionId },
      include: { user: true },
    });

    if (!session) return null;
    if (session.revokedAt) return null;
    if (session.expiresAt.getTime() <= Date.now()) return null;
    if (session.user.status === "SUSPENDED" || session.user.status === "CLOSED") return null;

    const secretOk = await verifySessionSecret(session.refreshTokenHash, parsed.secret);
    if (!secretOk) return null;

    return { userId: session.userId, sessionId: session.id };
  }

  private getRequestIp(req: Request): string | null {
    const xff = req.headers["x-forwarded-for"];
    if (typeof xff === "string" && xff.length > 0) {
      return xff.split(",")[0].trim();
    }

    return req.socket.remoteAddress ?? null;
  }

  private hashVerificationCode(code: string): string {
    return crypto.createHash("sha256").update(code).digest("hex");
  }

  private generateOtpCode(): string {
    return String(Math.floor(100000 + Math.random() * 900000));
  }

  private maskDestination(destination: string, channel: "EMAIL" | "SMS"): string {
    if (channel === "EMAIL") {
      const [local, domain] = destination.split("@");
      if (!local || !domain) return destination;
      return `${local.slice(0, 2)}***@${domain}`;
    }

    return destination.length > 4 ? `***${destination.slice(-4)}` : destination;
  }
}

export const authService = new AuthService();
TS

cat > apps/api/src/modules/verification/verification.routes.ts <<'TS'
import { Router } from "express";
import { verificationService } from "./verification.service";
import { simpleRateLimit } from "../../middleware/simple-rate-limit";

const router = Router();
const publicLimiter = simpleRateLimit({ keyPrefix: "verification:public", windowMs: 10 * 60 * 1000, max: 10 });

router.post("/auth/verify-email/request", publicLimiter, async (req, res) => {
  try {
    const email = String(req.body?.email ?? "").trim();
    if (!email) {
      return res.status(400).json({
        error: { code: "EMAIL_REQUIRED", message: "Email is required." },
      });
    }

    const result = await verificationService.requestEmailVerification(email);
    return res.json(result);
  } catch (error: any) {
    return res.status(500).json({
      error: {
        code: "VERIFY_EMAIL_REQUEST_FAILED",
        message: error?.message ?? "Failed to request verification email.",
      },
    });
  }
});

router.post("/auth/verify-email/confirm", publicLimiter, async (req, res) => {
  try {
    const email = String(req.body?.email ?? "").trim();
    const code = String(req.body?.code ?? "").trim();

    if (!email || !code) {
      return res.status(400).json({
        error: { code: "EMAIL_AND_CODE_REQUIRED", message: "Email and code are required." },
      });
    }

    const result = await verificationService.confirmEmailVerification(email, code);
    return res.json(result);
  } catch (error: any) {
    return res.status(400).json({
      error: {
        code: "VERIFY_EMAIL_CONFIRM_FAILED",
        message: error?.message ?? "Failed to verify email.",
      },
    });
  }
});

router.post("/auth/password/forgot", publicLimiter, async (req, res) => {
  try {
    const email = String(req.body?.email ?? "").trim();
    if (!email) {
      return res.status(400).json({
        error: { code: "EMAIL_REQUIRED", message: "Email is required." },
      });
    }

    const result = await verificationService.requestPasswordReset(email);
    return res.json(result);
  } catch (error: any) {
    return res.status(500).json({
      error: {
        code: "PASSWORD_FORGOT_FAILED",
        message: error?.message ?? "Failed to request password reset.",
      },
    });
  }
});

router.post("/auth/password/reset", publicLimiter, async (req, res) => {
  try {
    const token = String(req.body?.token ?? "").trim();
    const password = String(req.body?.password ?? "").trim();

    if (!token || !password) {
      return res.status(400).json({
        error: { code: "TOKEN_AND_PASSWORD_REQUIRED", message: "Token and password are required." },
      });
    }

    if (password.length < 10) {
      return res.status(400).json({
        error: {
          code: "PASSWORD_TOO_SHORT",
          message: "Password must be at least 10 characters.",
        },
      });
    }

    const result = await verificationService.resetPassword(token, password);
    return res.json(result);
  } catch (error: any) {
    return res.status(400).json({
      error: {
        code: "PASSWORD_RESET_FAILED",
        message: error?.message ?? "Failed to reset password.",
      },
    });
  }
});

export default router;
TS

cat > apps/api/src/modules/verification/verification.service.ts <<'TS'
import * as argon2 from "argon2";
import { prisma } from "../../lib/prisma";
import { notificationService } from "../notifications/notification.service";
import { notificationsConfig } from "../notifications/notifications.config";
import {
  addMinutes,
  generateOpaqueToken,
  generateOtpCode,
  hashForStorage,
  maskEmail,
  normalizeEmail,
} from "./verification.utils";

const CONTACT_VERIFICATION_PURPOSE = "CONTACT_VERIFICATION" as const;

export class VerificationService {
  async requestEmailVerification(emailInput: string) {
    const email = normalizeEmail(emailInput);

    const user = await prisma.user.findFirst({
      where: { email },
    });

    if (!user) {
      return { ok: true, message: "If an account exists, a verification email has been sent." };
    }

    if ((user as any).emailVerifiedAt) {
      return { ok: true, message: "Email already verified." };
    }

    await prisma.verificationChallenge.updateMany({
      where: {
        userId: user.id,
        channel: "EMAIL",
        purpose: CONTACT_VERIFICATION_PURPOSE,
        status: "PENDING",
      },
      data: {
        status: "CANCELLED",
      },
    });

    const code = generateOtpCode();
    const destinationHash = hashForStorage(email);
    const codeHash = hashForStorage(code);

    await prisma.verificationChallenge.create({
      data: {
        userId: user.id,
        channel: "EMAIL",
        purpose: CONTACT_VERIFICATION_PURPOSE,
        destinationMasked: maskEmail(email),
        destinationHash,
        codeHash,
        expiresAt: addMinutes(notificationsConfig.verificationOtpMinutes),
        maxAttempts: 5,
        status: "PENDING",
      },
    });

    await notificationService.sendVerificationOtpEmail({
      userId: user.id,
      to: email,
      code,
    });

    return {
      ok: true,
      message: "If an account exists, a verification email has been sent.",
    };
  }

  async confirmEmailVerification(emailInput: string, codeInput: string) {
    const email = normalizeEmail(emailInput);
    const destinationHash = hashForStorage(email);
    const codeHash = hashForStorage(codeInput.trim());

    const challenge = await prisma.verificationChallenge.findFirst({
      where: {
        channel: "EMAIL",
        purpose: CONTACT_VERIFICATION_PURPOSE,
        destinationHash,
        status: "PENDING",
      },
      orderBy: { createdAt: "desc" },
    });

    if (!challenge) {
      throw new Error("Invalid or expired verification code.");
    }

    const now = new Date();

    if (challenge.expiresAt <= now) {
      await prisma.verificationChallenge.update({
        where: { id: challenge.id },
        data: { status: "EXPIRED" },
      });
      throw new Error("Invalid or expired verification code.");
    }

    if (challenge.attemptCount >= challenge.maxAttempts) {
      await prisma.verificationChallenge.update({
        where: { id: challenge.id },
        data: { status: "LOCKED" },
      });
      throw new Error("Too many verification attempts. Request a new code.");
    }

    if (challenge.codeHash !== codeHash) {
      const nextAttempts = challenge.attemptCount + 1;
      await prisma.verificationChallenge.update({
        where: { id: challenge.id },
        data: {
          attemptCount: nextAttempts,
          status: nextAttempts >= challenge.maxAttempts ? "LOCKED" : "PENDING",
        },
      });
      throw new Error("Invalid or expired verification code.");
    }

    await prisma.$transaction([
      prisma.verificationChallenge.update({
        where: { id: challenge.id },
        data: {
          consumedAt: now,
          status: "VERIFIED",
        },
      }),
      prisma.user.update({
        where: { id: challenge.userId },
        data: { emailVerifiedAt: now },
      }),
    ]);

    return { ok: true, message: "Email verified successfully." };
  }

  async requestPasswordReset(emailInput: string) {
    const email = normalizeEmail(emailInput);

    const user = await prisma.user.findFirst({
      where: { email },
    });

    if (!user) {
      return { ok: true, message: "If an account exists, a reset email has been sent." };
    }

    await prisma.verificationChallenge.updateMany({
      where: {
        userId: user.id,
        channel: "EMAIL",
        purpose: "PASSWORD_RESET",
        status: "PENDING",
      },
      data: {
        status: "CANCELLED",
      },
    });

    const token = generateOpaqueToken();
    const destinationHash = hashForStorage(email);
    const codeHash = hashForStorage(token);

    await prisma.verificationChallenge.create({
      data: {
        userId: user.id,
        channel: "EMAIL",
        purpose: "PASSWORD_RESET",
        destinationMasked: maskEmail(email),
        destinationHash,
        codeHash,
        expiresAt: addMinutes(notificationsConfig.resetLinkMinutes),
        maxAttempts: 5,
        status: "PENDING",
      },
    });

    const resetUrl = `${notificationsConfig.appBaseUrl}/reset-password?token=${encodeURIComponent(token)}`;

    await notificationService.sendPasswordResetEmail({
      userId: user.id,
      to: email,
      resetUrl,
    });

    return {
      ok: true,
      message: "If an account exists, a reset email has been sent.",
    };
  }

  async resetPassword(tokenInput: string, password: string) {
    const codeHash = hashForStorage(tokenInput.trim());

    const challenge = await prisma.verificationChallenge.findFirst({
      where: {
        channel: "EMAIL",
        purpose: "PASSWORD_RESET",
        codeHash,
        status: "PENDING",
      },
      orderBy: { createdAt: "desc" },
    });

    if (!challenge) {
      throw new Error("Invalid or expired reset token.");
    }

    const now = new Date();

    if (challenge.expiresAt <= now) {
      await prisma.verificationChallenge.update({
        where: { id: challenge.id },
        data: { status: "EXPIRED" },
      });
      throw new Error("Invalid or expired reset token.");
    }

    const newPasswordHash = await argon2.hash(password);

    await prisma.$transaction([
      prisma.verificationChallenge.update({
        where: { id: challenge.id },
        data: {
          consumedAt: now,
          status: "VERIFIED",
        },
      }),
      prisma.user.update({
        where: { id: challenge.userId },
        data: { passwordHash: newPasswordHash },
      }),
      prisma.session.updateMany({
        where: {
          userId: challenge.userId,
          revokedAt: null,
        },
        data: {
          revokedAt: now,
        },
      }),
    ]);

    return { ok: true, message: "Password reset successfully." };
  }
}

export const verificationService = new VerificationService();
TS

cat > apps/api/src/lib/session-auth.ts <<'TS'
import argon2 from "argon2";
import crypto from "crypto";
import type { Request, Response } from "express";

export const SESSION_COOKIE_NAME = "dcapx_session";

const SESSION_TTL_DAYS = 30;

function getCookieAttributes(expiresAt: Date): string {
  const isProduction = process.env.NODE_ENV === "production";
  const sameSite = process.env.SESSION_COOKIE_SAMESITE ?? "Lax";
  const maxAge = Math.max(0, Math.floor((expiresAt.getTime() - Date.now()) / 1000));
  return `Path=/; HttpOnly; SameSite=${sameSite}; Max-Age=${maxAge}; ${
    isProduction ? "Secure; " : ""
  }Expires=${expiresAt.toUTCString()}`;
}

export function createSessionSecret(): string {
  return crypto.randomBytes(32).toString("hex");
}

export async function hashSessionSecret(secret: string): Promise<string> {
  return argon2.hash(secret);
}

export async function verifySessionSecret(hash: string, secret: string): Promise<boolean> {
  try {
    return await argon2.verify(hash, secret);
  } catch {
    return false;
  }
}

export function buildSessionCookieValue(sessionId: string, secret: string): string {
  return `${sessionId}.${secret}`;
}

export function parseSessionCookieValue(value: string | undefined | null): {
  sessionId: string;
  secret: string;
} | null {
  if (!value) return null;

  const firstDot = value.indexOf(".");
  if (firstDot <= 0) return null;

  const sessionId = value.slice(0, firstDot).trim();
  const secret = value.slice(firstDot + 1).trim();

  if (!sessionId || !secret) return null;

  return { sessionId, secret };
}

export function getCookieFromRequest(req: Request, name: string): string | null {
  const raw = req.headers.cookie;
  if (!raw) return null;

  const parts = raw.split(";").map((part) => part.trim());
  for (const part of parts) {
    const eqIdx = part.indexOf("=");
    if (eqIdx === -1) continue;

    const key = part.slice(0, eqIdx).trim();
    const value = part.slice(eqIdx + 1).trim();

    if (key === name) {
      return decodeURIComponent(value);
    }
  }

  return null;
}

export function getSessionExpiryDate(): Date {
  const d = new Date();
  d.setDate(d.getDate() + SESSION_TTL_DAYS);
  return d;
}

export function setSessionCookie(res: Response, sessionCookieValue: string, expiresAt: Date) {
  res.setHeader(
    "Set-Cookie",
    `${SESSION_COOKIE_NAME}=${encodeURIComponent(sessionCookieValue)}; ${getCookieAttributes(expiresAt)}`
  );
}

export function clearSessionCookie(res: Response) {
  const expiresAt = new Date(0);
  res.setHeader(
    "Set-Cookie",
    `${SESSION_COOKIE_NAME}=; ${getCookieAttributes(expiresAt)}`
  );
}
TS

cat > apps/api/src/modules/notifications/notifications.config.ts <<'TS'
export type EmailProviderName = "console" | "resend";

const isProduction = process.env.NODE_ENV === "production";

function requireEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}

const emailProvider = (process.env.EMAIL_PROVIDER ??
  (isProduction ? "resend" : process.env.RESEND_API_KEY ? "resend" : "console")) as EmailProviderName;

if (isProduction && emailProvider === "console") {
  throw new Error("EMAIL_PROVIDER=console is not allowed in production");
}

export const notificationsConfig = {
  appBaseUrl: process.env.APP_BASE_URL ?? "http://localhost:3002",
  emailProvider,
  emailFrom: isProduction
    ? requireEnv("EMAIL_FROM")
    : process.env.EMAIL_FROM ?? "DCapX <no-reply@dcapitalx.local>",
  resendApiKey: process.env.RESEND_API_KEY ?? "",
  otpHmacSecret: isProduction
    ? requireEnv("OTP_HMAC_SECRET")
    : process.env.OTP_HMAC_SECRET ?? "local-dev-only-otp-secret-change-me",
  verificationOtpMinutes: Number(process.env.VERIFICATION_OTP_MINUTES ?? 10),
  resetLinkMinutes: Number(process.env.RESET_LINK_MINUTES ?? 30),
};
TS

echo "P0 hardening patch applied."
echo "Next suggested commands:"
echo "  pnpm --filter api build"
echo "  docker compose config"
echo "  git diff -- . ':(exclude)*.bak.*'"
