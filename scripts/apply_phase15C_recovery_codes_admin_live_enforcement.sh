#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])

def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)

def read(path: Path) -> str:
    if not path.exists():
        raise SystemExit(f"Missing file: {path}")
    return path.read_text()

schema = root / "apps/api/prisma/schema.prisma"
schema_text = read(schema)
if "model MfaRecoveryCode" not in schema_text:
    schema_text = schema_text.rstrip() + """

model MfaRecoveryCode {
  id         String    @id @default(cuid())
  userId     String
  codeHash   String    @unique
  consumedAt DateTime?
  createdAt  DateTime  @default(now())

  @@index([userId, consumedAt])
}
"""
    write(schema, schema_text)

migration = root / "apps/api/prisma/migrations/20260410_phase15c_recovery_codes/migration.sql"
if not migration.exists():
    write(migration, """CREATE TABLE IF NOT EXISTS "MfaRecoveryCode" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "codeHash" TEXT NOT NULL,
  "consumedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "MfaRecoveryCode_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "MfaRecoveryCode_codeHash_key"
  ON "MfaRecoveryCode" ("codeHash");

CREATE INDEX IF NOT EXISTS "MfaRecoveryCode_userId_consumedAt_idx"
  ON "MfaRecoveryCode" ("userId", "consumedAt");
""")

mfa_service = root / "apps/api/src/modules/auth/mfa.service.ts"
write(mfa_service, """import crypto from "crypto";

import { authenticator } from "otplib";

import { ApiError } from "../../lib/errors/api-error";
import { prisma } from "../../lib/prisma";

authenticator.options = {
  step: 30,
  window: 1,
};

type BeginEnrollmentInput = {
  label?: string;
};

type ActivateEnrollmentInput = {
  factorId?: string;
  token?: string;
};

type ChallengeInput = {
  token?: string;
};

type RecoveryCodesInput = {
  count?: number;
};

type RecoveryCodeChallengeInput = {
  code?: string;
};

class MfaService {
  async beginTotpEnrollment(userId: string, input: BeginEnrollmentInput) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, email: true, username: true },
    });

    if (!user) {
      throw new ApiError({
        statusCode: 404,
        code: "USER_NOT_FOUND",
        message: "User not found.",
      });
    }

    const activeFactor = await prisma.mfaFactor.findFirst({
      where: {
        userId,
        type: "TOTP",
        status: "ACTIVE",
        revokedAt: null,
      },
      orderBy: { createdAt: "desc" },
    });

    if (activeFactor) {
      throw new ApiError({
        statusCode: 409,
        code: "MFA_TOTP_ALREADY_ACTIVE",
        message: "A TOTP factor is already active for this account.",
      });
    }

    await prisma.mfaFactor.updateMany({
      where: { userId, type: "TOTP", status: "PENDING" },
      data: { status: "REVOKED", revokedAt: new Date() },
    });

    const secret = authenticator.generateSecret();
    const secretEncrypted = this.encryptSecret(secret);

    const factor = await prisma.mfaFactor.create({
      data: {
        userId,
        type: "TOTP",
        status: "PENDING",
        label: input.label?.trim() || "Authenticator app",
        secretEncrypted,
      },
    });

    const issuer = process.env.MFA_TOTP_ISSUER?.trim() || "DCapX";
    const accountName = user.email || user.username || user.id;
    const otpauthUrl = authenticator.keyuri(accountName, issuer, secret);

    return {
      ok: true,
      factorId: factor.id,
      issuer,
      accountName,
      secret,
      otpauthUrl,
    };
  }

  async activateTotpEnrollment(userId: string, input: ActivateEnrollmentInput) {
    const factorId = input.factorId?.trim();
    const token = input.token?.trim();

    if (!factorId || !token) {
      throw new ApiError({
        statusCode: 400,
        code: "MFA_TOTP_ACTIVATION_INVALID_INPUT",
        message: "factorId and token are required.",
      });
    }

    const factor = await prisma.mfaFactor.findFirst({
      where: { id: factorId, userId, type: "TOTP", status: "PENDING" },
    });

    if (!factor) {
      throw new ApiError({
        statusCode: 404,
        code: "MFA_TOTP_FACTOR_NOT_FOUND",
        message: "Pending TOTP factor not found.",
      });
    }

    const secret = this.decryptSecret(factor.secretEncrypted);
    const valid = authenticator.check(token, secret);

    if (!valid) {
      throw new ApiError({
        statusCode: 400,
        code: "MFA_TOTP_INVALID_TOKEN",
        message: "The provided TOTP code is invalid.",
      });
    }

    const now = new Date();

    await prisma.$transaction([
      prisma.mfaFactor.updateMany({
        where: {
          userId,
          type: "TOTP",
          status: "ACTIVE",
          id: { not: factor.id },
        },
        data: { status: "REVOKED", revokedAt: now },
      }),
      prisma.mfaFactor.update({
        where: { id: factor.id },
        data: { status: "ACTIVE", activatedAt: now, revokedAt: null },
      }),
    ]);

    return {
      ok: true,
      factorId: factor.id,
      activatedAtUtc: now.toISOString(),
      method: "TOTP",
    };
  }

  async challengeTotp(userId: string, sessionId: string | undefined, input: ChallengeInput) {
    const token = input.token?.trim();

    if (!token) {
      throw new ApiError({
        statusCode: 400,
        code: "MFA_TOTP_TOKEN_REQUIRED",
        message: "A TOTP token is required.",
      });
    }

    if (!sessionId) {
      throw new ApiError({
        statusCode: 401,
        code: "UNAUTHENTICATED",
        message: "Authentication required.",
      });
    }

    const factor = await prisma.mfaFactor.findFirst({
      where: {
        userId,
        type: "TOTP",
        status: "ACTIVE",
        revokedAt: null,
      },
      orderBy: { activatedAt: "desc" },
    });

    if (!factor) {
      throw new ApiError({
        statusCode: 404,
        code: "MFA_TOTP_NOT_ENROLLED",
        message: "No active TOTP factor was found for this account.",
      });
    }

    const secret = this.decryptSecret(factor.secretEncrypted);
    const valid = authenticator.check(token, secret);

    if (!valid) {
      throw new ApiError({
        statusCode: 400,
        code: "MFA_TOTP_INVALID_TOKEN",
        message: "The provided TOTP code is invalid.",
      });
    }

    const now = new Date();

    await prisma.session.update({
      where: { id: sessionId },
      data: {
        mfaMethod: "TOTP",
        mfaVerifiedAt: now,
      },
    });

    return {
      ok: true,
      method: "TOTP",
      mfaVerifiedAtUtc: now.toISOString(),
    };
  }

  async regenerateRecoveryCodes(userId: string, input: RecoveryCodesInput = {}) {
    const activeFactor = await prisma.mfaFactor.findFirst({
      where: {
        userId,
        type: "TOTP",
        status: "ACTIVE",
        revokedAt: null,
      },
      orderBy: { activatedAt: "desc" },
      select: { id: true },
    });

    if (!activeFactor) {
      throw new ApiError({
        statusCode: 409,
        code: "MFA_RECOVERY_CODES_REQUIRES_TOTP",
        message: "Activate TOTP before generating recovery codes.",
      });
    }

    const requestedCount = Number(input.count ?? 10);
    const count = Number.isFinite(requestedCount)
      ? Math.max(8, Math.min(12, Math.trunc(requestedCount)))
      : 10;

    const recoveryCodes = Array.from({ length: count }, () => this.generateRecoveryCode());
    const now = new Date();

    await prisma.$transaction([
      prisma.mfaRecoveryCode.deleteMany({
        where: { userId },
      }),
      prisma.mfaRecoveryCode.createMany({
        data: recoveryCodes.map((code) => ({
          userId,
          codeHash: this.hashRecoveryCode(code),
          consumedAt: null,
          createdAt: now,
        })),
      }),
    ]);

    return {
      ok: true,
      codes: recoveryCodes,
      count,
      generatedAtUtc: now.toISOString(),
      method: "RECOVERY_CODE",
    };
  }

  async challengeRecoveryCode(
    userId: string,
    sessionId: string | undefined,
    input: RecoveryCodeChallengeInput,
  ) {
    const code = input.code?.trim();

    if (!code) {
      throw new ApiError({
        statusCode: 400,
        code: "MFA_RECOVERY_CODE_REQUIRED",
        message: "A recovery code is required.",
      });
    }

    if (!sessionId) {
      throw new ApiError({
        statusCode: 401,
        code: "UNAUTHENTICATED",
        message: "Authentication required.",
      });
    }

    const codeHash = this.hashRecoveryCode(code);
    const record = await prisma.mfaRecoveryCode.findFirst({
      where: {
        userId,
        codeHash,
        consumedAt: null,
      },
      orderBy: { createdAt: "desc" },
    });

    if (!record) {
      throw new ApiError({
        statusCode: 400,
        code: "MFA_RECOVERY_CODE_INVALID",
        message: "The provided recovery code is invalid.",
      });
    }

    const now = new Date();

    await prisma.$transaction([
      prisma.mfaRecoveryCode.update({
        where: { id: record.id },
        data: { consumedAt: now },
      }),
      prisma.session.update({
        where: { id: sessionId },
        data: {
          mfaMethod: "RECOVERY_CODE",
          mfaVerifiedAt: now,
        },
      }),
    ]);

    return {
      ok: true,
      method: "RECOVERY_CODE",
      mfaVerifiedAtUtc: now.toISOString(),
    };
  }

  private encryptSecret(secret: string): string {
    const key = this.deriveKey();
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
    const encrypted = Buffer.concat([cipher.update(secret, "utf8"), cipher.final()]);
    const tag = cipher.getAuthTag();

    return [iv.toString("base64"), tag.toString("base64"), encrypted.toString("base64")].join(".");
  }

  private decryptSecret(secretEncrypted: string): string {
    const [ivB64, tagB64, dataB64] = secretEncrypted.split(".");
    if (!ivB64 || !tagB64 || !dataB64) {
      throw new ApiError({
        statusCode: 500,
        code: "MFA_TOTP_SECRET_INVALID",
        message: "Stored TOTP secret is invalid.",
      });
    }

    const key = this.deriveKey();
    const decipher = crypto.createDecipheriv("aes-256-gcm", key, Buffer.from(ivB64, "base64"));
    decipher.setAuthTag(Buffer.from(tagB64, "base64"));
    const decrypted = Buffer.concat([
      decipher.update(Buffer.from(dataB64, "base64")),
      decipher.final(),
    ]);

    return decrypted.toString("utf8");
  }

  private deriveKey(): Buffer {
    const raw = process.env.MFA_TOTP_ENCRYPTION_KEY?.trim();
    if (!raw) {
      throw new ApiError({
        statusCode: 500,
        code: "MFA_TOTP_ENCRYPTION_KEY_MISSING",
        message: "MFA encryption key is not configured.",
      });
    }

    return crypto.createHash("sha256").update(raw).digest();
  }

  private generateRecoveryCode(): string {
    const raw = crypto
      .randomBytes(8)
      .toString("base64url")
      .replace(/[^A-Za-z0-9]/g, "")
      .toUpperCase()
      .slice(0, 12);

    return `${raw.slice(0, 4)}-${raw.slice(4, 8)}-${raw.slice(8, 12)}`;
  }

  private hashRecoveryCode(code: string): string {
    const normalized = code.replace(/[^A-Za-z0-9]/g, "").toUpperCase();
    return crypto.createHash("sha256").update(normalized).digest("hex");
  }
}

export const mfaService = new MfaService();
""")

auth_controller = root / "apps/api/src/modules/auth/auth.controller.ts"
write(auth_controller, """import type { NextFunction, Request, Response } from "express";

import { authService, registerUser } from "./auth.service";
import { mfaService } from "./mfa.service";

export async function register(req: Request, res: Response, next: NextFunction) {
  try {
    const user = await registerUser(req.body);
    res.status(201).json({
      ok: true,
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
      },
    });
  } catch (error) {
    next(error);
  }
}

export async function login(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await authService.login(req, res, req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function getSession(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await authService.getSession(req);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function logout(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await authService.logout(req, res);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function requestPasswordReset(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await authService.requestPasswordReset(req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function resetPassword(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await authService.resetPassword(req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function sendOtp(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await authService.sendOtp(req.auth!.userId, req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function verifyOtp(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await authService.verifyOtp(req.auth!.userId, req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function enrollTotp(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await mfaService.beginTotpEnrollment(req.auth!.userId, req.body ?? {});
    res.status(201).json(result);
  } catch (error) {
    next(error);
  }
}

export async function activateTotp(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await mfaService.activateTotpEnrollment(req.auth!.userId, req.body ?? {});
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function challengeTotp(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await mfaService.challengeTotp(req.auth!.userId, req.auth?.sessionId, req.body ?? {});
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function regenerateRecoveryCodes(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await mfaService.regenerateRecoveryCodes(req.auth!.userId, req.body ?? {});
    res.status(201).json(result);
  } catch (error) {
    next(error);
  }
}

export async function challengeRecoveryCode(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await mfaService.challengeRecoveryCode(
      req.auth!.userId,
      req.auth?.sessionId,
      req.body ?? {},
    );
    res.json(result);
  } catch (error) {
    next(error);
  }
}
""")

auth_routes = root / "apps/api/src/modules/auth/auth.routes.ts"
write(auth_routes, """import { Router } from "express";

import {
  activateTotp,
  challengeRecoveryCode,
  challengeTotp,
  enrollTotp,
  getSession,
  login,
  logout,
  regenerateRecoveryCodes,
  register,
  requestPasswordReset,
  resetPassword,
  sendOtp,
  verifyOtp,
} from "./auth.controller";
import { requireAuth, requireRecentMfa } from "../../middleware/require-auth";
import { simpleRateLimit } from "../../middleware/simple-rate-limit";

const router = Router();

const registerLimiter = simpleRateLimit({ keyPrefix: "auth:register", windowMs: 10 * 60 * 1000, max: 10 });
const loginLimiter = simpleRateLimit({ keyPrefix: "auth:login", windowMs: 10 * 60 * 1000, max: 20 });
const passwordLimiter = simpleRateLimit({ keyPrefix: "auth:password", windowMs: 10 * 60 * 1000, max: 10 });
const otpLimiter = simpleRateLimit({ keyPrefix: "auth:otp", windowMs: 10 * 60 * 1000, max: 10 });
const mfaLimiter = simpleRateLimit({ keyPrefix: "auth:mfa", windowMs: 10 * 60 * 1000, max: 20 });

router.post("/auth/register", registerLimiter, register);
router.post("/auth/login", loginLimiter, login);
router.get("/auth/session", getSession);
router.post("/auth/logout", requireAuth, logout);
router.post("/auth/request-password-reset", passwordLimiter, requestPasswordReset);
router.post("/auth/reset-password", passwordLimiter, resetPassword);
router.post("/auth/send-otp", requireAuth, otpLimiter, sendOtp);
router.post("/auth/verify-otp", requireAuth, otpLimiter, verifyOtp);

router.post("/auth/mfa/totp/enroll", requireAuth, mfaLimiter, enrollTotp);
router.post("/auth/mfa/totp/activate", requireAuth, mfaLimiter, activateTotp);
router.post("/auth/mfa/totp/challenge", requireAuth, mfaLimiter, challengeTotp);

router.post(
  "/auth/mfa/recovery-codes/regenerate",
  requireAuth,
  requireRecentMfa(),
  mfaLimiter,
  regenerateRecoveryCodes,
);
router.post(
  "/auth/mfa/recovery-codes/challenge",
  requireAuth,
  mfaLimiter,
  challengeRecoveryCode,
);

export default router;
""")

require_auth = root / "apps/api/src/middleware/require-auth.ts"
write(require_auth, """import type { NextFunction, Request, Response } from "express";

import { ApiError } from "../lib/errors/api-error";
import { prisma } from "../lib/prisma";
import { authService } from "../modules/auth/auth.service";

export type AuthContext = {
  userId: string;
  sessionId?: string;
  roleCodes: string[];
  mfaSatisfied: boolean;
  mfaMethod?: string | null;
  mfaVerifiedAt?: Date | null;
};

declare global {
  namespace Express {
    interface Request {
      auth?: AuthContext;
    }
  }
}

async function buildAuthContext(req: Request): Promise<AuthContext | null> {
  const auth = await authService.resolveAuthFromRequest(req);
  if (!auth) {
    return null;
  }

  const roles = await prisma.roleAssignment.findMany({
    where: { userId: auth.userId },
    select: { roleCode: true },
  });

  return {
    userId: auth.userId,
    sessionId: auth.sessionId,
    roleCodes: roles.map((role) => role.roleCode),
    mfaSatisfied: Boolean(auth.mfaVerifiedAt),
    mfaMethod: auth.mfaMethod ?? null,
    mfaVerifiedAt: auth.mfaVerifiedAt ?? null,
  };
}

async function ensureAuthContext(req: Request, res: Response): Promise<AuthContext> {
  if (!req.auth) {
    await new Promise<void>((resolve, reject) => {
      void requireAuth(req, res, (error?: unknown) => {
        if (error) {
          reject(error);
          return;
        }
        resolve();
      });
    });
  }

  if (!req.auth) {
    throw new ApiError({
      statusCode: 401,
      code: "UNAUTHENTICATED",
      message: "Authentication required.",
    });
  }

  return req.auth;
}

function getMfaAgeMs(auth: AuthContext): number {
  const verifiedAt = auth.mfaVerifiedAt ? new Date(auth.mfaVerifiedAt).getTime() : 0;
  return verifiedAt ? Date.now() - verifiedAt : Number.POSITIVE_INFINITY;
}

function isRecentMfa(auth: AuthContext, maxAgeSeconds: number): boolean {
  const ageMs = getMfaAgeMs(auth);
  return Number.isFinite(ageMs) && ageMs <= maxAgeSeconds * 1000;
}

function getRequestedMode(req: Request): string | undefined {
  const bodyMode = typeof req.body?.mode === "string" ? req.body.mode : undefined;
  const queryMode =
    typeof req.query?.mode === "string"
      ? req.query.mode
      : Array.isArray(req.query?.mode)
        ? req.query.mode[0]
        : undefined;
  const headerMode = typeof req.headers["x-mode"] === "string" ? req.headers["x-mode"] : undefined;

  const mode = bodyMode ?? queryMode ?? headerMode;
  return mode ? String(mode).trim().toUpperCase() : undefined;
}

async function hasApprovedLiveEligibility(userId: string): Promise<boolean> {
  const approvedKycCase = await prisma.kycCase.findFirst({
    where: {
      userId,
      status: "APPROVED" as any,
    },
    select: { id: true },
    orderBy: { updatedAt: "desc" },
  });

  if (approvedKycCase) {
    return true;
  }

  const legacyKycDelegate = (prisma as any).kyc;
  if (legacyKycDelegate?.findFirst) {
    const approvedLegacyKyc = await legacyKycDelegate.findFirst({
      where: {
        userId,
        status: "APPROVED",
      },
      select: { id: true },
      orderBy: { updatedAt: "desc" },
    });

    if (approvedLegacyKyc) {
      return true;
    }
  }

  return false;
}

export async function requireAuth(req: Request, _res: Response, next: NextFunction) {
  try {
    const auth = await buildAuthContext(req);
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

export function requireRole(...allowedRoleCodes: string[]) {
  const allowed = new Set(allowedRoleCodes);

  return async function requireRoleMiddleware(req: Request, res: Response, next: NextFunction) {
    try {
      const auth = await ensureAuthContext(req, res);
      const hasRole = auth.roleCodes.some((roleCode) => allowed.has(roleCode));

      if (!hasRole) {
        throw new ApiError({
          statusCode: 403,
          code: "FORBIDDEN",
          message: "You do not have permission to perform this action.",
        });
      }

      next();
    } catch (error) {
      next(error);
    }
  };
}

export function requireRecentMfa(maxAgeSeconds = 15 * 60) {
  return async function requireRecentMfaMiddleware(req: Request, res: Response, next: NextFunction) {
    try {
      const auth = await ensureAuthContext(req, res);
      const fresh = isRecentMfa(auth, maxAgeSeconds);

      req.auth = {
        ...auth,
        mfaSatisfied: fresh,
      };

      if (!fresh) {
        throw new ApiError({
          statusCode: 401,
          code: "MFA_REQUIRED",
          message: "A recent MFA challenge is required for this action.",
          retryable: true,
        });
      }

      next();
    } catch (error) {
      next(error);
    }
  };
}

export function requireAdminRecentMfa(
  allowedRoleCodes: string[] = ["ADMIN", "AUDITOR"],
  maxAgeSeconds = 15 * 60,
) {
  return async function requireAdminRecentMfaMiddleware(req: Request, res: Response, next: NextFunction) {
    try {
      const auth = await ensureAuthContext(req, res);
      const allowed = new Set(allowedRoleCodes);
      const hasRole = auth.roleCodes.some((roleCode) => allowed.has(roleCode));

      if (!hasRole) {
        throw new ApiError({
          statusCode: 403,
          code: "FORBIDDEN",
          message: "Administrator or auditor access is required.",
        });
      }

      const fresh = isRecentMfa(auth, maxAgeSeconds);

      req.auth = {
        ...auth,
        mfaSatisfied: fresh,
      };

      if (!fresh) {
        throw new ApiError({
          statusCode: 401,
          code: "MFA_REQUIRED",
          message: "A recent MFA challenge is required for administrative access.",
          retryable: true,
        });
      }

      next();
    } catch (error) {
      next(error);
    }
  };
}

export function requireLiveModeEligible(maxAgeSeconds = 15 * 60) {
  return async function requireLiveModeEligibleMiddleware(req: Request, res: Response, next: NextFunction) {
    try {
      const requestedMode = getRequestedMode(req);
      if (requestedMode !== "LIVE") {
        return next();
      }

      const auth = await ensureAuthContext(req, res);
      const fresh = isRecentMfa(auth, maxAgeSeconds);

      req.auth = {
        ...auth,
        mfaSatisfied: fresh,
      };

      if (!fresh) {
        throw new ApiError({
          statusCode: 401,
          code: "MFA_REQUIRED",
          message: "A recent MFA challenge is required for LIVE mode.",
          retryable: true,
        });
      }

      const liveEligible = await hasApprovedLiveEligibility(auth.userId);
      if (!liveEligible) {
        throw new ApiError({
          statusCode: 403,
          code: "LIVE_MODE_NOT_ALLOWED",
          message: "Approved KYC is required for LIVE mode.",
        });
      }

      next();
    } catch (error) {
      next(error);
    }
  };
}
""")

legacy_auth = root / "apps/api/src/middleware/auth.ts"
write(legacy_auth, """import type { NextFunction, Request, Response } from "express";

import {
  requireAdminRecentMfa,
  requireAuth,
  requireRecentMfa,
} from "./require-auth";

export async function requireUser(req: Request, res: Response, next: NextFunction) {
  return requireAuth(req, res, next);
}

export function requireMfa(maxAgeSeconds = 15 * 60) {
  return requireRecentMfa(maxAgeSeconds);
}

export function requireAdminMfa(maxAgeSeconds = 15 * 60) {
  return requireAdminRecentMfa(["ADMIN", "AUDITOR"], maxAgeSeconds);
}

export function authFromJwt(_req: Request, _res: Response, next: NextFunction) {
  next();
}
""")

print("Patched schema.prisma, recovery-code migration, mfa.service.ts, auth.controller.ts, auth.routes.ts, require-auth.ts, and middleware/auth.ts.")
PY

echo "Pass 1.5C patch applied."
