#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys
from textwrap import dedent

root = Path(sys.argv[1])

def read(path: Path) -> str:
    if not path.exists():
        raise SystemExit(f"Missing file: {path}")
    return path.read_text()

def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)

# 1) .env.example
write(root / ".env.example", dedent("""\
# --- Postgres ---
POSTGRES_USER=dcapx
POSTGRES_PASSWORD=change-me
POSTGRES_DB=dcapx

# --- App secrets (used directly when Vault is disabled) ---
ADMIN_KEY=change-me
JWT_SECRET=change-me
OTP_HMAC_SECRET=change-me
MFA_TOTP_ENCRYPTION_KEY=change-me
RESEND_API_KEY=
EMAIL_FROM=DCapX <no-reply@dcapitalx.local>

# --- App settings ---
NODE_ENV=development
APP_BASE_URL=http://localhost:3000
APP_CORS_ORIGINS=http://localhost:3000
EMAIL_PROVIDER=console
REDIS_URL=redis://redis:6379
MFA_TOTP_ISSUER=DCapX

# --- Database connection string ---
# Prisma migrations run before server bootstrap in the current Docker flow,
# so DATABASE_URL still needs to be available in the container environment.
DATABASE_URL=postgresql://dcapx:change-me@pg:5432/dcapx?schema=public

# --- Optional Vault bootstrap (AppRole) ---
VAULT_ENABLED=false
VAULT_ADDR=http://vault:8200
VAULT_MOUNT_PATH=approle
VAULT_ROLE_ID=
# Prefer VAULT_SECRET_ID_FILE in Docker/production. Keep VAULT_SECRET_ID for local dev only.
VAULT_SECRET_ID=
VAULT_SECRET_ID_FILE=
VAULT_SECRET_PATH=secret/data/dcapx/api
# When true, Vault-loaded values replace existing non-empty env vars.
VAULT_OVERRIDE_ENV=false
"""))

# 2) Compose env passthrough
for compose_name in ["docker-compose.yml", "docker-compose.prod.yml"]:
    p = root / compose_name
    s = read(p)
    if "MFA_TOTP_ISSUER:" not in s:
        s, n = re.subn(
            r'(\n\s+OTP_HMAC_SECRET:\s+\$\{OTP_HMAC_SECRET(?::-[^}]*)?\}\n)',
            r'\1        MFA_TOTP_ISSUER: ${MFA_TOTP_ISSUER:-DCapX}\n        MFA_TOTP_ENCRYPTION_KEY: ${MFA_TOTP_ENCRYPTION_KEY:-}\n',
            s,
            count=1,
        )
        if n == 0:
            raise SystemExit(f"Could not patch {compose_name}: OTP_HMAC_SECRET line not found")
    write(p, s)

# 3) Prisma schema: Session MFA fields
schema_path = root / "apps/api/prisma/schema.prisma"
schema = read(schema_path)
if "mfaVerifiedAt DateTime?" not in schema:
    schema, n = re.subn(
        r'(model Session \{.*?revokedAt DateTime\?\n)',
        r'\1\n mfaMethod String?\n\n mfaVerifiedAt DateTime?\n',
        schema,
        count=1,
        flags=re.S,
    )
    if n == 0:
        raise SystemExit("Could not patch apps/api/prisma/schema.prisma: Session block not found")
write(schema_path, schema)

# 4) Migration
migration_dir = root / "apps/api/prisma/migrations/20260411213000_phase15b_session_mfa"
migration_dir.mkdir(parents=True, exist_ok=True)
write(migration_dir / "migration.sql", dedent("""\
ALTER TABLE "Session"
  ADD COLUMN IF NOT EXISTS "mfaMethod" TEXT,
  ADD COLUMN IF NOT EXISTS "mfaVerifiedAt" TIMESTAMP(3);
"""))

# 5) MFA service
write(root / "apps/api/src/modules/auth/mfa.service.ts", dedent("""\
import crypto from "crypto";

import { authenticator } from "otplib";

import { ApiError } from "../../lib/errors/api-error";
import { prisma } from "../../lib/prisma";

authenticator.options = {
  step: 30,
  window: 1,
};

function requireEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new ApiError({
      statusCode: 500,
      code: "CONFIG_MISSING",
      message: `${name} is required.`,
    });
  }
  return value;
}

function getIssuer(): string {
  return process.env.MFA_TOTP_ISSUER?.trim() || "DCapX";
}

function getEncryptionKey(): Buffer {
  const raw = requireEnv("MFA_TOTP_ENCRYPTION_KEY");
  return crypto.createHash("sha256").update(raw).digest();
}

function encryptSecret(secret: string): string {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", getEncryptionKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(secret, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${iv.toString("hex")}:${tag.toString("hex")}:${ciphertext.toString("hex")}`;
}

function decryptSecret(payload: string): string {
  const [ivHex, tagHex, ciphertextHex] = payload.split(":");
  if (!ivHex || !tagHex || !ciphertextHex) {
    throw new ApiError({
      statusCode: 500,
      code: "MFA_SECRET_INVALID",
      message: "Stored MFA secret is invalid.",
    });
  }

  const decipher = crypto.createDecipheriv(
    "aes-256-gcm",
    getEncryptionKey(),
    Buffer.from(ivHex, "hex"),
  );
  decipher.setAuthTag(Buffer.from(tagHex, "hex"));
  const plaintext = Buffer.concat([
    decipher.update(Buffer.from(ciphertextHex, "hex")),
    decipher.final(),
  ]);
  return plaintext.toString("utf8");
}

type TotpEnrollmentBody = {
  label?: string;
};

type TotpVerifyBody = {
  code?: string;
};

class MfaService {
  async beginTotpEnrollment(userId: string, body: TotpEnrollmentBody = {}) {
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

    const manualEntryKey = authenticator.generateSecret();
    const accountLabel = body.label?.trim() || user.email || user.username || user.id;
    const now = new Date();

    await prisma.mfaFactor.updateMany({
      where: {
        userId,
        type: "TOTP",
        status: "PENDING",
        revokedAt: null,
      },
      data: {
        status: "REVOKED",
        revokedAt: now,
      },
    });

    const factor = await prisma.mfaFactor.create({
      data: {
        userId,
        type: "TOTP",
        status: "PENDING",
        label: body.label?.trim() || null,
        secretEncrypted: encryptSecret(manualEntryKey),
      },
    });

    return {
      ok: true,
      factorId: factor.id,
      type: "TOTP",
      issuer: getIssuer(),
      accountLabel,
      manualEntryKey,
      otpauthUrl: authenticator.keyuri(accountLabel, getIssuer(), manualEntryKey),
    };
  }

  async verifyTotpEnrollment(userId: string, body: TotpVerifyBody = {}) {
    const code = body.code?.trim().replace(/\s+/g, "");
    if (!code) {
      throw new ApiError({
        statusCode: 400,
        code: "MFA_CODE_REQUIRED",
        message: "TOTP code is required.",
      });
    }

    const factor = await prisma.mfaFactor.findFirst({
      where: {
        userId,
        type: "TOTP",
        status: "PENDING",
        revokedAt: null,
      },
      orderBy: { createdAt: "desc" },
    });

    if (!factor) {
      throw new ApiError({
        statusCode: 404,
        code: "MFA_ENROLLMENT_NOT_FOUND",
        message: "No pending TOTP enrollment was found.",
      });
    }

    const secret = decryptSecret(factor.secretEncrypted);
    if (!authenticator.check(code, secret)) {
      throw new ApiError({
        statusCode: 400,
        code: "MFA_CODE_INVALID",
        message: "Invalid TOTP code.",
      });
    }

    const now = new Date();
    await prisma.$transaction([
      prisma.mfaFactor.updateMany({
        where: {
          userId,
          type: "TOTP",
          status: "ACTIVE",
          revokedAt: null,
          id: { not: factor.id },
        },
        data: {
          status: "REVOKED",
          revokedAt: now,
        },
      }),
      prisma.mfaFactor.update({
        where: { id: factor.id },
        data: {
          status: "ACTIVE",
          activatedAt: now,
          revokedAt: null,
        },
      }),
    ]);

    return {
      ok: true,
      factorId: factor.id,
      status: "ACTIVE",
      activatedAtUtc: now.toISOString(),
    };
  }

  async beginTotpChallenge(userId: string, sessionId: string) {
    const factor = await prisma.mfaFactor.findFirst({
      where: {
        userId,
        type: "TOTP",
        status: "ACTIVE",
        revokedAt: null,
      },
      select: { id: true },
    });

    if (!factor) {
      throw new ApiError({
        statusCode: 404,
        code: "MFA_FACTOR_NOT_FOUND",
        message: "No active TOTP factor is enrolled for this account.",
      });
    }

    const session = await prisma.session.findUnique({
      where: { id: sessionId },
      select: { mfaVerifiedAt: true, mfaMethod: true },
    });

    return {
      ok: true,
      required: true,
      factorId: factor.id,
      mfaSatisfied: Boolean(session?.mfaVerifiedAt),
      mfaMethod: session?.mfaMethod ?? null,
      mfaVerifiedAtUtc: session?.mfaVerifiedAt?.toISOString() ?? null,
    };
  }

  async verifyTotpChallenge(userId: string, sessionId: string, body: TotpVerifyBody = {}) {
    const code = body.code?.trim().replace(/\s+/g, "");
    if (!code) {
      throw new ApiError({
        statusCode: 400,
        code: "MFA_CODE_REQUIRED",
        message: "TOTP code is required.",
      });
    }

    const factors = await prisma.mfaFactor.findMany({
      where: {
        userId,
        type: "TOTP",
        status: "ACTIVE",
        revokedAt: null,
      },
      select: {
        id: true,
        secretEncrypted: true,
      },
    });

    if (factors.length === 0) {
      throw new ApiError({
        statusCode: 404,
        code: "MFA_FACTOR_NOT_FOUND",
        message: "No active TOTP factor is enrolled for this account.",
      });
    }

    const isValid = factors.some((factor) => {
      const secret = decryptSecret(factor.secretEncrypted);
      return authenticator.check(code, secret);
    });

    if (!isValid) {
      throw new ApiError({
        statusCode: 400,
        code: "MFA_CODE_INVALID",
        message: "Invalid TOTP code.",
      });
    }

    const now = new Date();
    const updated = await prisma.session.updateMany({
      where: {
        id: sessionId,
        userId,
        revokedAt: null,
        expiresAt: { gt: now },
      },
      data: {
        mfaMethod: "TOTP",
        mfaVerifiedAt: now,
      },
    });

    if (updated.count === 0) {
      throw new ApiError({
        statusCode: 401,
        code: "SESSION_NOT_FOUND",
        message: "Active session not found.",
      });
    }

    return {
      ok: true,
      mfaSatisfied: true,
      mfaMethod: "TOTP",
      mfaVerifiedAtUtc: now.toISOString(),
    };
  }
}

export const mfaService = new MfaService();
"""))

# 6) auth.controller.ts
write(root / "apps/api/src/modules/auth/auth.controller.ts", dedent("""\
import type { NextFunction, Request, Response } from "express";

import { ApiError } from "../../lib/errors/api-error";
import { mfaService } from "./mfa.service";
import { authService, registerUser } from "./auth.service";

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

export async function beginTotpEnrollment(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await mfaService.beginTotpEnrollment(req.auth!.userId, req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function confirmTotpEnrollment(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await mfaService.verifyTotpEnrollment(req.auth!.userId, req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function beginTotpChallenge(req: Request, res: Response, next: NextFunction) {
  try {
    const sessionId = req.auth?.sessionId;
    if (!sessionId) {
      throw new ApiError({
        statusCode: 401,
        code: "SESSION_REQUIRED",
        message: "An authenticated session is required.",
      });
    }
    const result = await mfaService.beginTotpChallenge(req.auth!.userId, sessionId);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function confirmTotpChallenge(req: Request, res: Response, next: NextFunction) {
  try {
    const sessionId = req.auth?.sessionId;
    if (!sessionId) {
      throw new ApiError({
        statusCode: 401,
        code: "SESSION_REQUIRED",
        message: "An authenticated session is required.",
      });
    }
    const result = await mfaService.verifyTotpChallenge(req.auth!.userId, sessionId, req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}
"""))

# 7) auth.routes.ts
write(root / "apps/api/src/modules/auth/auth.routes.ts", dedent("""\
import { Router } from "express";

import { requireAuth } from "../../middleware/require-auth";
import { simpleRateLimit } from "../../middleware/simple-rate-limit";
import {
  beginTotpChallenge,
  beginTotpEnrollment,
  confirmTotpChallenge,
  confirmTotpEnrollment,
  getSession,
  login,
  logout,
  register,
  requestPasswordReset,
  resetPassword,
  sendOtp,
  verifyOtp,
} from "./auth.controller";

const router = Router();

const registerLimiter = simpleRateLimit({
  keyPrefix: "auth:register",
  windowMs: 10 * 60 * 1000,
  max: 10,
});

const loginLimiter = simpleRateLimit({
  keyPrefix: "auth:login",
  windowMs: 10 * 60 * 1000,
  max: 20,
});

const passwordLimiter = simpleRateLimit({
  keyPrefix: "auth:password",
  windowMs: 10 * 60 * 1000,
  max: 10,
});

const otpLimiter = simpleRateLimit({
  keyPrefix: "auth:otp",
  windowMs: 10 * 60 * 1000,
  max: 10,
});

const mfaLimiter = simpleRateLimit({
  keyPrefix: "auth:mfa",
  windowMs: 10 * 60 * 1000,
  max: 20,
});

router.post("/auth/register", registerLimiter, register);
router.post("/auth/login", loginLimiter, login);
router.get("/auth/session", getSession);
router.post("/auth/logout", requireAuth, logout);
router.post("/auth/request-password-reset", passwordLimiter, requestPasswordReset);
router.post("/auth/reset-password", passwordLimiter, resetPassword);
router.post("/auth/send-otp", requireAuth, otpLimiter, sendOtp);
router.post("/auth/verify-otp", requireAuth, otpLimiter, verifyOtp);

router.post("/auth/mfa/totp/enroll", requireAuth, mfaLimiter, beginTotpEnrollment);
router.post("/auth/mfa/totp/enroll/verify", requireAuth, mfaLimiter, confirmTotpEnrollment);
router.post("/auth/mfa/totp/challenge", requireAuth, mfaLimiter, beginTotpChallenge);
router.post("/auth/mfa/totp/challenge/verify", requireAuth, mfaLimiter, confirmTotpChallenge);

export default router;
"""))

# 8) require-auth.ts
write(root / "apps/api/src/middleware/require-auth.ts", dedent("""\
import type { NextFunction, Request, Response } from "express";

import { ApiError } from "../lib/errors/api-error";
import { prisma } from "../lib/prisma";
import { authService } from "../modules/auth/auth.service";

type AuthContext = {
  userId: string;
  sessionId?: string;
  roleCodes: string[];
  mfaSatisfied: boolean;
  mfaVerifiedAt?: Date | null;
  mfaMethod?: string | null;
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

  const [roles, session] = await Promise.all([
    prisma.roleAssignment.findMany({
      where: { userId: auth.userId },
      select: { roleCode: true },
    }),
    auth.sessionId
      ? prisma.session.findUnique({
          where: { id: auth.sessionId },
          select: { mfaVerifiedAt: true, mfaMethod: true },
        })
      : Promise.resolve(null),
  ]);

  return {
    userId: auth.userId,
    sessionId: auth.sessionId,
    roleCodes: roles.map((role) => role.roleCode),
    mfaSatisfied: Boolean(session?.mfaVerifiedAt),
    mfaVerifiedAt: session?.mfaVerifiedAt ?? null,
    mfaMethod: session?.mfaMethod ?? null,
  };
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
      if (!req.auth) {
        await requireAuth(req, res, (error?: unknown) => {
          if (error) throw error;
        });
      }

      if (!req.auth) {
        throw new ApiError({
          statusCode: 401,
          code: "UNAUTHENTICATED",
          message: "Authentication required.",
        });
      }

      const hasRole = req.auth.roleCodes.some((roleCode) => allowed.has(roleCode));
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
      if (!req.auth) {
        await requireAuth(req, res, (error?: unknown) => {
          if (error) throw error;
        });
      }

      if (!req.auth) {
        throw new ApiError({
          statusCode: 401,
          code: "UNAUTHENTICATED",
          message: "Authentication required.",
        });
      }

      if (!req.auth.mfaVerifiedAt) {
        throw new ApiError({
          statusCode: 403,
          code: "MFA_REQUIRED",
          message: "Recent MFA verification is required.",
        });
      }

      const ageMs = Date.now() - req.auth.mfaVerifiedAt.getTime();
      if (ageMs > maxAgeSeconds * 1000) {
        throw new ApiError({
          statusCode: 403,
          code: "MFA_EXPIRED",
          message: "Your MFA verification has expired. Please verify again.",
        });
      }

      req.auth.mfaSatisfied = true;
      next();
    } catch (error) {
      next(error);
    }
  };
}
"""))

# 9) middleware/auth.ts legacy compatibility
write(root / "apps/api/src/middleware/auth.ts", dedent("""\
import type { NextFunction, Request, Response } from "express";

import { ApiError } from "../lib/errors/api-error";
import { requireAuth as canonicalRequireAuth, requireRecentMfa } from "./require-auth";

export type AuthedRequest = Request & {
  auth?: Express.Request["auth"];
  user?: { id: string; username: string };
};

export async function requireUser(req: AuthedRequest, res: Response, next: NextFunction) {
  try {
    await canonicalRequireAuth(req, res, (error?: unknown) => {
      if (error) {
        throw error;
      }
    });

    if (req.auth) {
      req.user = {
        id: req.auth.userId,
        username: req.auth.userId,
      };
    }

    next();
  } catch (error) {
    next(error);
  }
}

export const requireMfa = requireRecentMfa();

export function authFromJwt(_req: Request, _res: Response, next: NextFunction) {
  next(
    new ApiError({
      statusCode: 501,
      code: "LEGACY_AUTH_DISABLED",
      message:
        "Legacy auth middleware is disabled. Use the canonical session-based require-auth middleware instead.",
    }),
  );
}
"""))

print("Patched .env.example, compose files, schema/migration, auth routes/controllers, and MFA middleware/service")
PY

echo "Pass B patch applied."
echo "Next recommended commands:"
echo "  cd $ROOT"
echo "  pnpm --filter api prisma generate"
echo "  pnpm --filter api build"
echo "  bash scripts/verify_phase15B_real_totp_mfa.sh $ROOT"
