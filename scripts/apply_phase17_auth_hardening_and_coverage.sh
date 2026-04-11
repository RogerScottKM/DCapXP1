#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import sys

root = Path(sys.argv[1])

# package.json
pkg_path = root / "apps/api/package.json"
pkg = json.loads(pkg_path.read_text())
dev = pkg.setdefault("devDependencies", {})
for name, version in {
    "vitest": "^3.2.4",
    "supertest": "^7.1.1",
    "@types/supertest": "^6.0.3",
}.items():
    dev.setdefault(name, version)

scripts = pkg.setdefault("scripts", {})
scripts.setdefault("test", "vitest run")
scripts.setdefault("test:auth", "vitest run test/auth.service.audit.test.ts test/require-auth.audit.test.ts")

pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

# vitest config
(root / "apps/api/vitest.config.ts").write_text('''import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    globals: true,
    include: ["test/**/*.test.ts"],
    clearMocks: true,
    restoreMocks: true,
    mockReset: true,
  },
});
''')

# require-auth.ts with denial auditing
(root / "apps/api/src/middleware/require-auth.ts").write_text('''import type { NextFunction, Request, Response } from "express";

import { ApiError } from "../lib/errors/api-error";
import { prisma } from "../lib/prisma";
import { recordSecurityAudit } from "../lib/service/security-audit";
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

async function auditAuthDecision(
  req: Request,
  auth: AuthContext | null,
  action: string,
  metadata: Record<string, unknown> = {},
): Promise<void> {
  await recordSecurityAudit({
    actorType: auth?.userId ? "USER" : "ANONYMOUS",
    actorId: auth?.userId ?? null,
    action,
    resourceType: "ROUTE",
    resourceId: req.originalUrl || req.path || null,
    req,
    metadata: {
      method: req.method,
      path: req.originalUrl || req.path,
      ...metadata,
    },
  });
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
      await auditAuthDecision(req, null, "AUTHZ_UNAUTHENTICATED_DENIED", {
        reason: "AUTH_REQUIRED",
      });
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
        await auditAuthDecision(req, auth, "AUTHZ_ROLE_DENIED", {
          allowedRoleCodes,
          currentRoleCodes: auth.roleCodes,
        });
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
        await auditAuthDecision(req, auth, "AUTHZ_MFA_REQUIRED_DENIED", {
          maxAgeSeconds,
          mfaMethod: auth.mfaMethod ?? null,
          mfaVerifiedAt: auth.mfaVerifiedAt?.toISOString?.() ?? auth.mfaVerifiedAt ?? null,
        });
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
        await auditAuthDecision(req, auth, "AUTHZ_ADMIN_ROLE_DENIED", {
          allowedRoleCodes,
          currentRoleCodes: auth.roleCodes,
        });
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
        await auditAuthDecision(req, auth, "AUTHZ_ADMIN_MFA_REQUIRED_DENIED", {
          maxAgeSeconds,
          mfaMethod: auth.mfaMethod ?? null,
          mfaVerifiedAt: auth.mfaVerifiedAt?.toISOString?.() ?? auth.mfaVerifiedAt ?? null,
        });
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
        await auditAuthDecision(req, auth, "AUTHZ_LIVE_MFA_REQUIRED_DENIED", {
          requestedMode,
          maxAgeSeconds,
          mfaMethod: auth.mfaMethod ?? null,
          mfaVerifiedAt: auth.mfaVerifiedAt?.toISOString?.() ?? auth.mfaVerifiedAt ?? null,
        });
        throw new ApiError({
          statusCode: 401,
          code: "MFA_REQUIRED",
          message: "A recent MFA challenge is required for LIVE mode.",
          retryable: true,
        });
      }

      const liveEligible = await hasApprovedLiveEligibility(auth.userId);
      if (!liveEligible) {
        await auditAuthDecision(req, auth, "LIVE_MODE_DENIED", {
          requestedMode,
          reason: "APPROVED_KYC_REQUIRED",
        });
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
''')

# auth.service.ts with auth audit coverage
(root / "apps/api/src/modules/auth/auth.service.ts").write_text('''import argon2 from "argon2";
import crypto from "crypto";
import type { Request, Response } from "express";

import { ApiError } from "../../lib/errors/api-error";
import { prisma } from "../../lib/prisma";
import { recordSecurityAudit } from "../../lib/service/security-audit";
import { writeAuditEvent } from "../../lib/service/audit";
import { withTx } from "../../lib/service/tx";
import { parseDto } from "../../lib/service/zod";
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
import { registerDto } from "./auth.dto";
import { mapRegisterDtoToUserCreate } from "./auth.mappers";

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
      include: { profile: true, roles: true },
    });

    if (!user) {
      await recordSecurityAudit({
        actorType: "ANONYMOUS",
        actorId: null,
        action: "AUTH_LOGIN_FAILED",
        resourceType: "AUTH_SESSION",
        resourceId: null,
        req,
        metadata: { identifier },
      });
      throw new ApiError({
        statusCode: 401,
        code: "LOGIN_INVALID_CREDENTIALS",
        message: "Invalid credentials.",
      });
    }

    if (user.status === "SUSPENDED" || user.status === "CLOSED") {
      await recordSecurityAudit({
        actorType: "USER",
        actorId: user.id,
        action: "AUTH_LOGIN_BLOCKED",
        resourceType: "AUTH_SESSION",
        resourceId: null,
        req,
        metadata: { status: user.status },
      });
      throw new ApiError({
        statusCode: 403,
        code: "ACCOUNT_UNAVAILABLE",
        message: "This account is not available for sign-in.",
      });
    }

    const passwordOk = await argon2.verify(user.passwordHash, password);
    if (!passwordOk) {
      await recordSecurityAudit({
        actorType: "USER",
        actorId: user.id,
        action: "AUTH_LOGIN_FAILED",
        resourceType: "AUTH_SESSION",
        resourceId: null,
        req,
        metadata: { identifier },
      });
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

    await recordSecurityAudit({
      actorType: "USER",
      actorId: user.id,
      action: "AUTH_LOGIN_SUCCEEDED",
      resourceType: "AUTH_SESSION",
      resourceId: session.id,
      req,
      metadata: {
        sessionId: session.id,
        expiresAtUtc: session.expiresAt.toISOString(),
      },
    });

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
    const auth = await this.resolveAuthFromRequest(req);
    const parsed = parseSessionCookieValue(getCookieFromRequest(req, SESSION_COOKIE_NAME));

    if (parsed?.sessionId) {
      await prisma.session.updateMany({
        where: { id: parsed.sessionId, revokedAt: null },
        data: { revokedAt: new Date() },
      });
    }

    clearSessionCookie(res);

    await recordSecurityAudit({
      actorType: auth?.userId ? "USER" : "ANONYMOUS",
      actorId: auth?.userId ?? null,
      action: "AUTH_LOGOUT",
      resourceType: "AUTH_SESSION",
      resourceId: parsed?.sessionId ?? null,
      req,
      metadata: {
        sessionId: parsed?.sessionId ?? null,
      },
    });

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

    const result = await verificationService.requestPasswordReset(email);

    await recordSecurityAudit({
      actorType: "ANONYMOUS",
      actorId: null,
      action: "AUTH_PASSWORD_RESET_REQUESTED",
      resourceType: "PASSWORD_RESET",
      resourceId: null,
      metadata: { email },
    });

    return result;
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

    const result = await verificationService.resetPassword(token, newPassword);

    await recordSecurityAudit({
      actorType: "ANONYMOUS",
      actorId: null,
      action: "AUTH_PASSWORD_RESET_COMPLETED",
      resourceType: "PASSWORD_RESET",
      resourceId: null,
      metadata: { tokenPresent: Boolean(token) },
    });

    return result;
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

    await recordSecurityAudit({
      actorType: "USER",
      actorId: userId,
      action: "AUTH_OTP_SENT",
      resourceType: "OTP_CHALLENGE",
      resourceId: null,
      metadata: {
        channel,
        expiresAtUtc: expiresAt.toISOString(),
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
    if (codeHash != record.codeHash) {
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

    await recordSecurityAudit({
      actorType: "USER",
      actorId: userId,
      action: "AUTH_OTP_VERIFIED",
      resourceType: "OTP_CHALLENGE",
      resourceId: record.id,
      metadata: { channel },
    });

    return {
      ok: true,
      message: channel === "EMAIL" ? "Your email has been verified." : "Your phone number has been verified.",
      emailVerifiedAtUtc: updatedUser.emailVerifiedAt?.toISOString() ?? null,
      phoneVerifiedAtUtc: updatedUser.phoneVerifiedAt?.toISOString() ?? null,
    };
  }

  async resolveAuthFromRequest(req: Request): Promise<{
    userId: string;
    sessionId: string;
    mfaMethod: string | null;
    mfaVerifiedAt: Date | null;
  } | null> {
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

    return {
      userId: session.userId,
      sessionId: session.id,
      mfaMethod: session.mfaMethod ?? null,
      mfaVerifiedAt: session.mfaVerifiedAt ?? null,
    };
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
''')

# tests
(root / "apps/api/test").mkdir(parents=True, exist_ok=True)
(root / "apps/api/test/auth.service.audit.test.ts").write_text('''import { beforeEach, describe, expect, it, vi } from "vitest";

const prismaMock = {
  user: { findFirst: vi.fn(), findUnique: vi.fn() },
  session: { create: vi.fn(), updateMany: vi.fn(), findUnique: vi.fn() },
  verificationCode: { updateMany: vi.fn(), create: vi.fn(), findFirst: vi.fn(), update: vi.fn() },
  $transaction: vi.fn(),
};

const recordSecurityAudit = vi.fn();
const setSessionCookie = vi.fn();
const clearSessionCookie = vi.fn();
const verificationService = {
  requestPasswordReset: vi.fn(),
  resetPassword: vi.fn(),
};

vi.mock("argon2", () => ({
  default: {
    verify: vi.fn(),
    hash: vi.fn(),
  },
}));

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/service/security-audit", () => ({ recordSecurityAudit }));
vi.mock("../src/lib/service/audit", () => ({ writeAuditEvent: vi.fn() }));
vi.mock("../src/lib/service/tx", () => ({ withTx: vi.fn() }));
vi.mock("../src/lib/service/zod", () => ({ parseDto: vi.fn() }));
vi.mock("../src/modules/verification/verification.service", () => ({ verificationService }));
vi.mock("../src/modules/auth/auth.dto", () => ({ registerDto: {} }));
vi.mock("../src/modules/auth/auth.mappers", () => ({ mapRegisterDtoToUserCreate: vi.fn() }));
vi.mock("../src/lib/session-auth", () => ({
  buildSessionCookieValue: vi.fn(() => "session-cookie"),
  clearSessionCookie,
  createSessionSecret: vi.fn(() => "secret"),
  getCookieFromRequest: vi.fn(() => "raw-cookie"),
  getSessionExpiryDate: vi.fn(() => new Date("2030-01-01T00:00:00.000Z")),
  hashSessionSecret: vi.fn(async () => "secret-hash"),
  parseSessionCookieValue: vi.fn(() => ({ sessionId: "session-1", secret: "secret" })),
  SESSION_COOKIE_NAME: "dcapx_session",
  setSessionCookie,
  verifySessionSecret: vi.fn(async () => true),
}));

import argon2 from "argon2";
import { authService } from "../src/modules/auth/auth.service";

describe("auth.service audit coverage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    prismaMock.$transaction.mockImplementation(async (ops: any[]) => Promise.all(ops));
  });

  it("records AUTH_LOGIN_SUCCEEDED on successful login", async () => {
    prismaMock.user.findFirst.mockResolvedValue({
      id: "user-1",
      email: "user@example.com",
      username: "user1",
      status: "ACTIVE",
      passwordHash: "hash",
      profile: null,
      roles: [],
    });
    (argon2.verify as any).mockResolvedValue(true);
    prismaMock.session.create.mockResolvedValue({
      id: "session-1",
      expiresAt: new Date("2030-01-01T00:00:00.000Z"),
    });

    const req: any = { headers: { "user-agent": "Vitest" }, socket: { remoteAddress: "127.0.0.1" } };
    const res: any = {};

    const result = await authService.login(req, res, { identifier: "user@example.com", password: "password" });

    expect(result.ok).toBe(true);
    expect(setSessionCookie).toHaveBeenCalled();
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "AUTH_LOGIN_SUCCEEDED",
        actorId: "user-1",
        resourceId: "session-1",
      }),
    );
  });

  it("records AUTH_LOGIN_FAILED when credentials are invalid", async () => {
    prismaMock.user.findFirst.mockResolvedValue(null);

    const req: any = { headers: {}, socket: { remoteAddress: "127.0.0.1" } };
    const res: any = {};

    await expect(authService.login(req, res, { identifier: "missing@example.com", password: "bad" })).rejects.toMatchObject({
      code: "LOGIN_INVALID_CREDENTIALS",
    });

    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "AUTH_LOGIN_FAILED",
      }),
    );
  });

  it("records AUTH_LOGOUT on logout", async () => {
    prismaMock.session.findUnique.mockResolvedValue({
      id: "session-1",
      userId: "user-1",
      mfaMethod: null,
      mfaVerifiedAt: null,
      revokedAt: null,
      expiresAt: new Date("2030-01-01T00:00:00.000Z"),
      refreshTokenHash: "hash",
      user: { status: "ACTIVE" },
    });
    prismaMock.session.updateMany.mockResolvedValue({ count: 1 });

    const req: any = { headers: {}, socket: { remoteAddress: "127.0.0.1" } };
    const res: any = {};

    const result = await authService.logout(req, res);
    expect(result.ok).toBe(true);
    expect(clearSessionCookie).toHaveBeenCalled();
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "AUTH_LOGOUT",
      }),
    );
  });
});
''')

(root / "apps/api/test/require-auth.audit.test.ts").write_text('''import type { Request, Response } from "express";
import { beforeEach, describe, expect, it, vi } from "vitest";

const prismaMock = {
  roleAssignment: { findMany: vi.fn() },
  kycCase: { findFirst: vi.fn() },
};

const recordSecurityAudit = vi.fn();
const resolveAuthFromRequest = vi.fn();

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));
vi.mock("../src/lib/service/security-audit", () => ({ recordSecurityAudit }));
vi.mock("../src/modules/auth/auth.service", () => ({
  authService: {
    resolveAuthFromRequest,
  },
}));

import { requireLiveModeEligible, requireRecentMfa, requireRole } from "../src/middleware/require-auth";

function createReq(overrides: Partial<Request> = {}): Request {
  return {
    method: "POST",
    originalUrl: "/api/test",
    path: "/api/test",
    body: {},
    query: {},
    headers: {},
    ...overrides,
  } as Request;
}

function createRes(): Response {
  return {} as Response;
}

function runMiddleware(mw: (req: Request, res: Response, next: (error?: unknown) => void) => Promise<void> | void, req: Request) {
  return new Promise<unknown>((resolve) => {
    mw(req, createRes(), (error?: unknown) => resolve(error));
  });
}

describe("require-auth audit coverage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    prismaMock.roleAssignment.findMany.mockResolvedValue([]);
    prismaMock.kycCase.findFirst.mockResolvedValue(null);
  });

  it("records AUTHZ_MFA_REQUIRED_DENIED when recent MFA is missing", async () => {
    resolveAuthFromRequest.mockResolvedValue({
      userId: "user-1",
      sessionId: "session-1",
      mfaMethod: null,
      mfaVerifiedAt: null,
    });

    const req = createReq();
    const error = await runMiddleware(requireRecentMfa(), req);

    expect(error).toMatchObject({ code: "MFA_REQUIRED" });
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({ action: "AUTHZ_MFA_REQUIRED_DENIED" }),
    );
  });

  it("records AUTHZ_ROLE_DENIED when role is missing", async () => {
    resolveAuthFromRequest.mockResolvedValue({
      userId: "user-1",
      sessionId: "session-1",
      mfaMethod: null,
      mfaVerifiedAt: new Date().toISOString(),
    });
    prismaMock.roleAssignment.findMany.mockResolvedValue([{ roleCode: "USER" }]);

    const req = createReq();
    const error = await runMiddleware(requireRole("ADMIN"), req);

    expect(error).toMatchObject({ code: "FORBIDDEN" });
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({ action: "AUTHZ_ROLE_DENIED" }),
    );
  });

  it("records LIVE_MODE_DENIED when approved KYC is missing for LIVE mode", async () => {
    resolveAuthFromRequest.mockResolvedValue({
      userId: "user-1",
      sessionId: "session-1",
      mfaMethod: "TOTP",
      mfaVerifiedAt: new Date().toISOString(),
    });
    prismaMock.roleAssignment.findMany.mockResolvedValue([{ roleCode: "ADMIN" }]);
    prismaMock.kycCase.findFirst.mockResolvedValue(null);

    const req = createReq({ body: { mode: "LIVE" } });
    const error = await runMiddleware(requireLiveModeEligible(), req);

    expect(error).toMatchObject({ code: "LIVE_MODE_NOT_ALLOWED" });
    expect(recordSecurityAudit).toHaveBeenCalledWith(
      expect.objectContaining({ action: "LIVE_MODE_DENIED" }),
    );
  });
});
''')

print("Patched package.json, require-auth.ts, auth.service.ts, vitest config, and auth audit tests for Phase 1.7.")
PY

echo "Phase 1.7 patch applied."
