#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])


def read(path: Path) -> str:
    if not path.exists():
        raise SystemExit(f"Missing file: {path}")
    return path.read_text()


def write(path: Path, text: str) -> None:
    path.write_text(text)


def ensure_contains(path: Path, snippet: str) -> None:
    s = read(path)
    if snippet not in s:
        s += ("\n" if not s.endswith("\n") else "") + snippet
        write(path, s)

# 1) require-auth.ts
require_auth = root / "apps/api/src/middleware/require-auth.ts"
write(require_auth, '''import type { NextFunction, Request, Response } from "express";

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
      const verifiedAt = auth.mfaVerifiedAt ? new Date(auth.mfaVerifiedAt).getTime() : 0;
      const ageMs = verifiedAt ? Date.now() - verifiedAt : Number.POSITIVE_INFINITY;
      const isFresh = Number.isFinite(ageMs) && ageMs <= maxAgeSeconds * 1000;

      req.auth = {
        ...auth,
        mfaSatisfied: isFresh,
      };

      if (!isFresh) {
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
''')

# 2) legacy middleware/auth.ts
legacy_auth = root / "apps/api/src/middleware/auth.ts"
write(legacy_auth, '''import type { NextFunction, Request, Response } from "express";

import { ApiError } from "../lib/errors/api-error";
import type { AuthContext } from "./require-auth";
import { requireAuth, requireRecentMfa } from "./require-auth";

export type AuthedRequest = Request & {
  auth?: AuthContext;
  user?: { id: string; username: string };
};

export async function requireUser(req: AuthedRequest, res: Response, next: NextFunction) {
  try {
    await new Promise<void>((resolve, reject) => {
      void requireAuth(req, res, (error?: unknown) => {
        if (error) {
          reject(error);
          return;
        }
        resolve();
      });
    });

    if (!req.auth) {
      throw new ApiError({
        statusCode: 401,
        code: "UNAUTHENTICATED",
        message: "Authentication required.",
      });
    }

    req.user = { id: req.auth.userId, username: req.auth.userId };
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
      message: "Legacy auth middleware is disabled. Use the canonical session-based require-auth middleware instead.",
    }),
  );
}
''')

# 3) mfa.service.ts
mfa_service = root / "apps/api/src/modules/auth/mfa.service.ts"
write(mfa_service, '''import crypto from "crypto";

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
      where: {
        userId,
        type: "TOTP",
        status: "PENDING",
      },
      data: {
        status: "REVOKED",
        revokedAt: new Date(),
      },
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
      where: {
        id: factorId,
        userId,
        type: "TOTP",
        status: "PENDING",
      },
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
}

export const mfaService = new MfaService();
''')

# 4) auth.controller.ts
controller = root / "apps/api/src/modules/auth/auth.controller.ts"
write(controller, '''import type { NextFunction, Request, Response } from "express";

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
''')

# 5) auth.routes.ts
routes = root / "apps/api/src/modules/auth/auth.routes.ts"
write(routes, '''import { Router } from "express";

import {
  activateTotp,
  challengeTotp,
  enrollTotp,
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

export default router;
''')

# 6) auth.service.ts patch resolver only
service = root / "apps/api/src/modules/auth/auth.service.ts"
s = read(service)
pattern = re.compile(r'  async resolveAuthFromRequest\(req: Request\): Promise<\{ userId: string; sessionId: string \} \| null> \{.*?^  private getRequestIp', re.DOTALL | re.MULTILINE)
replacement = '''  async resolveAuthFromRequest(req: Request): Promise<{\n    userId: string;\n    sessionId: string;\n    mfaMethod: string | null;\n    mfaVerifiedAt: Date | null;\n  } | null> {\n    const rawCookie = getCookieFromRequest(req, SESSION_COOKIE_NAME);\n    const parsed = parseSessionCookieValue(rawCookie);\n    if (!parsed) return null;\n\n    const session = await prisma.session.findUnique({\n      where: { id: parsed.sessionId },\n      include: { user: true },\n    });\n\n    if (!session) return null;\n    if (session.revokedAt) return null;\n    if (session.expiresAt.getTime() <= Date.now()) return null;\n    if (session.user.status === "SUSPENDED" || session.user.status === "CLOSED") return null;\n\n    const secretOk = await verifySessionSecret(session.refreshTokenHash, parsed.secret);\n    if (!secretOk) return null;\n\n    return {\n      userId: session.userId,\n      sessionId: session.id,\n      mfaMethod: session.mfaMethod ?? null,\n      mfaVerifiedAt: session.mfaVerifiedAt ?? null,\n    };\n  }\n\n  private getRequestIp'''
new_s, n = pattern.subn(replacement, s, count=1)
if n == 0:
    raise SystemExit("Could not patch auth.service.ts resolveAuthFromRequest block")
write(service, new_s)

# 7) ensure env example + compose contain MFA vars
for rel in [Path('.env.example')]:
    p = root / rel
    s = read(p)
    if 'MFA_TOTP_ISSUER=' not in s:
        s += ('\n' if not s.endswith('\n') else '') + 'MFA_TOTP_ISSUER=DCapX\n'
    if 'MFA_TOTP_ENCRYPTION_KEY=' not in s:
        s += 'MFA_TOTP_ENCRYPTION_KEY=change-me\n'
    write(p, s)

for rel in [Path('docker-compose.yml'), Path('docker-compose.prod.yml')]:
    p = root / rel
    s = read(p)
    if 'MFA_TOTP_ISSUER:' in s:
        write(p, s)
        continue
    for needle in [
        '        OTP_HMAC_SECRET: ${OTP_HMAC_SECRET}\n',
        '        OTP_HMAC_SECRET: ${OTP_HMAC_SECRET:-}\n',
        '        OTP_HMAC_SECRET: ${OTP_HMAC_SECRET:-change-me}\n',
    ]:
        if needle in s:
            s = s.replace(
                needle,
                needle + '        MFA_TOTP_ISSUER: ${MFA_TOTP_ISSUER:-DCapX}\n        MFA_TOTP_ENCRYPTION_KEY: ${MFA_TOTP_ENCRYPTION_KEY:-}\n',
                1,
            )
            break
    else:
        raise SystemExit(f'Could not patch {rel}: OTP_HMAC_SECRET line not found')
    write(p, s)

print('Patched require-auth.ts, middleware/auth.ts, auth.controller.ts, auth.routes.ts, auth.service.ts, added mfa.service.ts, and ensured MFA env/compose settings.')
PY

echo "Pass B2 patch applied."
