#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])

def write(path_str: str, content: str):
    path = root / path_str
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)

# New shared audit helper
write("apps/api/src/lib/service/security-audit.ts", '''import type { Request } from "express";

import { prisma } from "../prisma";

type SecurityAuditInput = {
  actorType?: string;
  actorId?: string | null;
  subjectType?: string | null;
  subjectId?: string | null;
  action: string;
  resourceType?: string | null;
  resourceId?: string | null;
  ipAddress?: string | null;
  userAgent?: string | null;
  metadata?: unknown;
  req?: Pick<Request, "ip" | "headers"> & { socket?: { remoteAddress?: string | null } };
};

function extractIp(input: SecurityAuditInput): string | null {
  if (input.ipAddress?.trim()) {
    return input.ipAddress.trim();
  }

  const forwarded = input.req?.headers?.["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.trim()) {
    return forwarded.split(",")[0].trim();
  }

  if (Array.isArray(forwarded) && forwarded.length > 0 && forwarded[0]?.trim()) {
    return forwarded[0].split(",")[0].trim();
  }

  const reqIp = input.req?.ip?.trim();
  if (reqIp) {
    return reqIp;
  }

  return input.req?.socket?.remoteAddress?.trim() ?? null;
}

function extractUserAgent(input: SecurityAuditInput): string | null {
  if (input.userAgent?.trim()) {
    return input.userAgent.trim();
  }

  const header = input.req?.headers?.["user-agent"];
  if (typeof header === "string" && header.trim()) {
    return header.trim();
  }

  if (Array.isArray(header) && header.length > 0 && header[0]?.trim()) {
    return header[0].trim();
  }

  return null;
}

export async function recordSecurityAudit(input: SecurityAuditInput): Promise<void> {
  try {
    await prisma.auditEvent.create({
      data: {
        actorType: input.actorType ?? (input.actorId ? "USER" : "SYSTEM"),
        actorId: input.actorId ?? null,
        subjectType: input.subjectType ?? null,
        subjectId: input.subjectId ?? null,
        action: input.action,
        resourceType: input.resourceType ?? null,
        resourceId: input.resourceId ?? null,
        ipAddress: extractIp(input),
        userAgent: extractUserAgent(input),
        metadata: input.metadata === undefined ? undefined : (input.metadata as any),
      },
    });
  } catch (error) {
    console.error("[security-audit] failed to persist audit event", {
      action: input.action,
      actorId: input.actorId ?? null,
      resourceType: input.resourceType ?? null,
      resourceId: input.resourceId ?? null,
      error,
    });
  }
}
''')

# New middleware for privileged route access logging
write("apps/api/src/middleware/audit-privileged.ts", '''import type { NextFunction, Request, Response } from "express";

import { recordSecurityAudit } from "../lib/service/security-audit";

export function auditPrivilegedRequest(
  action: string,
  resourceType?: string,
  resourceId?: string | ((req: Request) => string | undefined),
  metadataBuilder?: (req: Request) => Record<string, unknown> | undefined,
) {
  return async function auditPrivilegedRequestMiddleware(req: Request, res: Response, next: NextFunction) {
    try {
      await recordSecurityAudit({
        actorId: req.auth?.userId ?? null,
        action,
        resourceType: resourceType ?? null,
        resourceId: typeof resourceId === "function" ? resourceId(req) ?? null : resourceId ?? null,
        metadata: metadataBuilder?.(req),
        req,
      });
    } catch (error) {
      console.error("[security-audit] privileged request middleware error", error);
    }

    next();
  };
}
''')

# Overwrite auth.controller.ts with audit-aware MFA calls
write("apps/api/src/modules/auth/auth.controller.ts", '''import type { NextFunction, Request, Response } from "express";

import { authService, registerUser } from "./auth.service";
import { mfaService } from "./mfa.service";

function buildAuditContext(req: Request) {
  return {
    sessionId: req.auth?.sessionId ?? null,
    ipAddress: req.ip ?? null,
    userAgent: req.get("user-agent") ?? null,
  };
}

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
    const result = await mfaService.beginTotpEnrollment(req.auth!.userId, req.body ?? {}, buildAuditContext(req));
    res.status(201).json(result);
  } catch (error) {
    next(error);
  }
}

export async function activateTotp(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await mfaService.activateTotpEnrollment(
      req.auth!.userId,
      req.auth?.sessionId,
      req.body ?? {},
      buildAuditContext(req),
    );
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function challengeTotp(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await mfaService.challengeTotp(
      req.auth!.userId,
      req.auth?.sessionId,
      req.body ?? {},
      buildAuditContext(req),
    );
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function regenerateRecoveryCodes(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await mfaService.regenerateRecoveryCodes(
      req.auth!.userId,
      req.auth?.sessionId,
      req.body ?? {},
      buildAuditContext(req),
    );
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
      buildAuditContext(req),
    );
    res.json(result);
  } catch (error) {
    next(error);
  }
}
''')

# Overwrite mfa.service.ts with audited and revocation-hardened implementation
write("apps/api/src/modules/auth/mfa.service.ts", '''import crypto from "crypto";

import { authenticator } from "otplib";

import { ApiError } from "../../lib/errors/api-error";
import { prisma } from "../../lib/prisma";
import { recordSecurityAudit } from "../../lib/service/security-audit";

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

type AuditContext = {
  sessionId?: string | null;
  ipAddress?: string | null;
  userAgent?: string | null;
};

class MfaService {
  async beginTotpEnrollment(userId: string, input: BeginEnrollmentInput, auditContext: AuditContext = {}) {
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

    await recordSecurityAudit({
      actorId: userId,
      action: "MFA_TOTP_ENROLLMENT_STARTED",
      resourceType: "MFA_FACTOR",
      resourceId: factor.id,
      metadata: {
        method: "TOTP",
        label: factor.label,
      },
      ipAddress: auditContext.ipAddress ?? null,
      userAgent: auditContext.userAgent ?? null,
    });

    return {
      ok: true,
      factorId: factor.id,
      issuer,
      accountName,
      secret,
      otpauthUrl,
    };
  }

  async activateTotpEnrollment(
    userId: string,
    sessionId: string | undefined,
    input: ActivateEnrollmentInput,
    auditContext: AuditContext = {},
  ) {
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
    let revokedOtherSessions = 0;

    await prisma.$transaction(async (tx) => {
      await tx.mfaFactor.updateMany({
        where: {
          userId,
          type: "TOTP",
          status: "ACTIVE",
          id: { not: factor.id },
        },
        data: { status: "REVOKED", revokedAt: now },
      });

      await tx.mfaFactor.update({
        where: { id: factor.id },
        data: { status: "ACTIVE", activatedAt: now, revokedAt: null },
      });

      if (sessionId) {
        const revoked = await tx.session.updateMany({
          where: {
            userId,
            revokedAt: null,
            id: { not: sessionId },
          },
          data: {
            revokedAt: now,
            mfaMethod: null,
            mfaVerifiedAt: null,
          },
        });
        revokedOtherSessions = revoked.count;

        await tx.session.updateMany({
          where: { id: sessionId },
          data: {
            mfaMethod: null,
            mfaVerifiedAt: null,
          },
        });
      } else {
        const revoked = await tx.session.updateMany({
          where: { userId, revokedAt: null },
          data: {
            revokedAt: now,
            mfaMethod: null,
            mfaVerifiedAt: null,
          },
        });
        revokedOtherSessions = revoked.count;
      }
    });

    await recordSecurityAudit({
      actorId: userId,
      action: "MFA_TOTP_ENROLLMENT_ACTIVATED",
      resourceType: "MFA_FACTOR",
      resourceId: factor.id,
      metadata: {
        method: "TOTP",
        revokedOtherSessions,
      },
      ipAddress: auditContext.ipAddress ?? null,
      userAgent: auditContext.userAgent ?? null,
    });

    if (revokedOtherSessions > 0) {
      await recordSecurityAudit({
        actorId: userId,
        action: "SESSION_REVOKED_AFTER_MFA_CHANGE",
        resourceType: "SESSION",
        resourceId: sessionId ?? null,
        metadata: {
          method: "TOTP",
          revokedOtherSessions,
        },
        ipAddress: auditContext.ipAddress ?? null,
        userAgent: auditContext.userAgent ?? null,
      });
    }

    return {
      ok: true,
      factorId: factor.id,
      activatedAtUtc: now.toISOString(),
      method: "TOTP",
      revokedOtherSessions,
    };
  }

  async challengeTotp(
    userId: string,
    sessionId: string | undefined,
    input: ChallengeInput,
    auditContext: AuditContext = {},
  ) {
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

    await recordSecurityAudit({
      actorId: userId,
      action: "MFA_CHALLENGE_SUCCEEDED",
      resourceType: "MFA_FACTOR",
      resourceId: factor.id,
      metadata: {
        method: "TOTP",
      },
      ipAddress: auditContext.ipAddress ?? null,
      userAgent: auditContext.userAgent ?? null,
    });

    return {
      ok: true,
      method: "TOTP",
      mfaVerifiedAtUtc: now.toISOString(),
    };
  }

  async regenerateRecoveryCodes(
    userId: string,
    sessionId: string | undefined,
    input: RecoveryCodesInput = {},
    auditContext: AuditContext = {},
  ) {
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
    let revokedOtherSessions = 0;

    await prisma.$transaction(async (tx) => {
      await tx.mfaRecoveryCode.deleteMany({ where: { userId } });
      await tx.mfaRecoveryCode.createMany({
        data: recoveryCodes.map((code) => ({
          userId,
          codeHash: this.hashRecoveryCode(code),
          consumedAt: null,
          createdAt: now,
        })),
      });

      if (sessionId) {
        const revoked = await tx.session.updateMany({
          where: {
            userId,
            revokedAt: null,
            id: { not: sessionId },
          },
          data: {
            revokedAt: now,
            mfaMethod: null,
            mfaVerifiedAt: null,
          },
        });
        revokedOtherSessions = revoked.count;

        await tx.session.updateMany({
          where: { id: sessionId },
          data: {
            mfaMethod: null,
            mfaVerifiedAt: null,
          },
        });
      } else {
        const revoked = await tx.session.updateMany({
          where: { userId, revokedAt: null },
          data: {
            revokedAt: now,
            mfaMethod: null,
            mfaVerifiedAt: null,
          },
        });
        revokedOtherSessions = revoked.count;
      }
    });

    await recordSecurityAudit({
      actorId: userId,
      action: "MFA_RECOVERY_CODES_REGENERATED",
      resourceType: "MFA_RECOVERY_CODE_SET",
      resourceId: userId,
      metadata: {
        count,
        revokedOtherSessions,
      },
      ipAddress: auditContext.ipAddress ?? null,
      userAgent: auditContext.userAgent ?? null,
    });

    if (revokedOtherSessions > 0) {
      await recordSecurityAudit({
        actorId: userId,
        action: "SESSION_REVOKED_AFTER_MFA_CHANGE",
        resourceType: "SESSION",
        resourceId: sessionId ?? null,
        metadata: {
          method: "RECOVERY_CODE",
          revokedOtherSessions,
        },
        ipAddress: auditContext.ipAddress ?? null,
        userAgent: auditContext.userAgent ?? null,
      });
    }

    return {
      ok: true,
      codes: recoveryCodes,
      count,
      generatedAtUtc: now.toISOString(),
      method: "RECOVERY_CODE",
      revokedOtherSessions,
    };
  }

  async challengeRecoveryCode(
    userId: string,
    sessionId: string | undefined,
    input: RecoveryCodeChallengeInput,
    auditContext: AuditContext = {},
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

    await recordSecurityAudit({
      actorId: userId,
      action: "MFA_CHALLENGE_SUCCEEDED",
      resourceType: "MFA_RECOVERY_CODE",
      resourceId: record.id,
      metadata: {
        method: "RECOVERY_CODE",
      },
      ipAddress: auditContext.ipAddress ?? null,
      userAgent: auditContext.userAgent ?? null,
    });

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
''')

# Overwrite privileged route files with audit middleware added
write("apps/api/src/routes/agents.ts", '''import { Router } from "express";
import type { Response } from "express";
import crypto from "crypto";

import { AgentKind } from "@prisma/client";
import { z } from "zod";

import { auditPrivilegedRequest } from "../middleware/audit-privileged";
import { requireUser, type AuthedRequest } from "../middleware/auth";
import { requireRecentMfa } from "../middleware/require-auth";
import { prisma } from "../prisma";

const router = Router();

const createAgentSchema = z.object({
  name: z.string().min(2).max(80),
  kind: z.nativeEnum(AgentKind).optional().default(AgentKind.MARKET_MAKER),
  aptivioTokenId: z.string().optional(),
});

router.post(
  "/",
  requireUser,
  requireRecentMfa(),
  auditPrivilegedRequest("AGENT_CREATE_REQUESTED", "AGENT"),
  async (req: AuthedRequest, res: Response) => {
    const body = createAgentSchema.parse(req.body);
    const { publicKey, privateKey } = crypto.generateKeyPairSync("ed25519");
    const publicKeyPem = publicKey.export({ format: "pem", type: "spki" }).toString("utf8");
    const privateKeyPem = privateKey.export({ format: "pem", type: "pkcs8" }).toString("utf8");

    const agent = await prisma.agent.create({
      data: {
        userId: req.user!.id,
        name: body.name,
        kind: body.kind,
        aptivioTokenId: body.aptivioTokenId ?? null,
        keys: {
          create: {
            publicKeyPem,
          },
        },
      },
      include: { keys: true },
    });

    return res.json({
      ok: true,
      agent: {
        id: agent.id,
        name: agent.name,
        status: agent.status,
        publicKeyPem,
      },
      privateKeyPem,
    });
  },
);

router.get("/", requireUser, async (req: AuthedRequest, res: Response) => {
  const agents = await prisma.agent.findMany({
    where: { userId: req.user!.id },
    include: {
      mandates: true,
      keys: { where: { revokedAt: null } },
    },
    orderBy: { createdAt: "desc" },
  });

  res.json({ ok: true, agents });
});

router.post(
  "/:agentId/keys/rotate",
  requireUser,
  requireRecentMfa(),
  auditPrivilegedRequest("AGENT_KEYS_ROTATE_REQUESTED", "AGENT", (req) => String(req.params.agentId)),
  async (req: AuthedRequest, res: Response) => {
    const agentId = String(req.params.agentId);
    const agent = await prisma.agent.findFirst({
      where: { id: agentId, userId: req.user!.id },
      include: { keys: { where: { revokedAt: null } } },
    });

    if (!agent) {
      return res.status(404).json({ error: "Agent not found" });
    }

    await prisma.agentKey.updateMany({
      where: { agentId, revokedAt: null },
      data: { revokedAt: new Date() },
    });

    const { publicKey, privateKey } = crypto.generateKeyPairSync("ed25519");
    const publicKeyPem = publicKey.export({ format: "pem", type: "spki" }).toString("utf8");
    const privateKeyPem = privateKey.export({ format: "pem", type: "pkcs8" }).toString("utf8");

    await prisma.agentKey.create({
      data: { agentId, publicKeyPem },
    });

    res.json({ ok: true, agentId, publicKeyPem, privateKeyPem });
  },
);

router.post(
  "/:agentId/revoke",
  requireUser,
  requireRecentMfa(),
  auditPrivilegedRequest("AGENT_REVOKE_REQUESTED", "AGENT", (req) => String(req.params.agentId)),
  async (req: AuthedRequest, res: Response) => {
    const agentId = String(req.params.agentId);
    const agent = await prisma.agent.findFirst({
      where: { id: agentId, userId: req.user!.id },
    });

    if (!agent) {
      return res.status(404).json({ error: "Agent not found" });
    }

    await prisma.$transaction([
      prisma.agent.update({
        where: { id: agentId },
        data: { status: "REVOKED" },
      }),
      prisma.agentKey.updateMany({
        where: { agentId, revokedAt: null },
        data: { revokedAt: new Date() },
      }),
      prisma.mandate.updateMany({
        where: { agentId, revokedAt: null },
        data: { status: "REVOKED", revokedAt: new Date() },
      }),
    ]);

    res.json({ ok: true });
  },
);

export default router;
''')

write("apps/api/src/routes/mandates.ts", '''import { Router } from "express";
import type { Response } from "express";

import { z } from "zod";

import { auditPrivilegedRequest } from "../middleware/audit-privileged";
import { requireUser, type AuthedRequest } from "../middleware/auth";
import { requireLiveModeEligible, requireRecentMfa } from "../middleware/require-auth";
import { prisma } from "../prisma";
import { parseDecimalToBigInt } from "../utils/quantums";

const router = Router();

const issueMandateSchema = z.object({
  action: z.enum(["TRADE", "WITHDRAW", "TRANSFER"]),
  market: z.string().min(3).max(40).optional(),
  maxNotionalPerDay: z.string().optional(),
  quoteDecimals: z.number().int().min(0).max(18).optional(),
  maxOrdersPerDay: z.number().int().min(0).max(1_000_000).optional(),
  notBefore: z.string().datetime().optional(),
  expiresAt: z.string().datetime(),
  constraints: z.any().optional(),
  mandateJwtHash: z.string().optional(),
});

router.post(
  "/agents/:agentId",
  requireUser,
  requireRecentMfa(),
  requireLiveModeEligible(),
  auditPrivilegedRequest("MANDATE_ISSUE_REQUESTED", "MANDATE", (req) => String(req.params.agentId)),
  async (req: AuthedRequest, res: Response) => {
    const agentId = String(req.params.agentId);
    const body = issueMandateSchema.parse(req.body);
    const agent = await prisma.agent.findFirst({
      where: { id: agentId, userId: req.user!.id },
    });

    if (!agent) {
      return res.status(404).json({ error: "Agent not found" });
    }

    const quoteDecimals = body.quoteDecimals ?? 6;
    const maxNotionalPerDay =
      body.maxNotionalPerDay && body.maxNotionalPerDay !== "0"
        ? parseDecimalToBigInt(body.maxNotionalPerDay, quoteDecimals)
        : 0n;

    const mandate = await prisma.mandate.create({
      data: {
        agentId,
        action: body.action,
        market: body.market ?? null,
        maxNotionalPerDay,
        maxOrdersPerDay: body.maxOrdersPerDay ?? 0,
        notBefore: body.notBefore ? new Date(body.notBefore) : new Date(),
        expiresAt: new Date(body.expiresAt),
        constraints: body.constraints ?? null,
        mandateJwtHash: body.mandateJwtHash ?? null,
        status: "ACTIVE",
      },
    });

    res.json({ ok: true, mandate });
  },
);

router.get("/agents/:agentId", requireUser, async (req: AuthedRequest, res: Response) => {
  const agentId = String(req.params.agentId);
  const agent = await prisma.agent.findFirst({
    where: { id: agentId, userId: req.user!.id },
  });

  if (!agent) {
    return res.status(404).json({ error: "Agent not found" });
  }

  const mandates = await prisma.mandate.findMany({
    where: { agentId },
    orderBy: { createdAt: "desc" },
  });

  res.json({ ok: true, mandates });
});

router.post(
  "/:mandateId/revoke",
  requireUser,
  requireRecentMfa(),
  auditPrivilegedRequest("MANDATE_REVOKE_REQUESTED", "MANDATE", (req) => String(req.params.mandateId)),
  async (req: AuthedRequest, res: Response) => {
    const mandateId = String(req.params.mandateId);
    const mandate = await prisma.mandate.findUnique({
      where: { id: mandateId },
      include: { agent: true },
    });

    if (!mandate || mandate.agent.userId !== req.user!.id) {
      return res.status(404).json({ error: "Mandate not found" });
    }

    await prisma.mandate.update({
      where: { id: mandateId },
      data: { status: "REVOKED", revokedAt: new Date() },
    });

    res.json({ ok: true });
  },
);

export default router;
''')

write("apps/api/src/modules/advisor/advisor.routes.ts", '''import { Router } from "express";
import type { NextFunction, Request, Response } from "express";

import { auditPrivilegedRequest } from "../../middleware/audit-privileged";
import {
  requireAdminRecentMfa,
  requireAuth,
  requireRecentMfa,
  requireRole,
} from "../../middleware/require-auth";
import { getAdvisorClientAptivioSummary } from "./advisor.controller";

const router = Router();

function requireAdvisorOrAdminRecentMfa(req: Request, res: Response, next: NextFunction) {
  const roleCodes = new Set(req.auth?.roleCodes ?? []);

  if (roleCodes.has("admin") || roleCodes.has("auditor")) {
    return requireAdminRecentMfa()(req, res, next);
  }

  return requireRecentMfa()(req, res, next);
}

router.get(
  "/advisor/clients/:clientId/aptivio-summary",
  requireAuth,
  requireRole("advisor", "admin"),
  requireAdvisorOrAdminRecentMfa,
  auditPrivilegedRequest(
    "ADVISOR_CLIENT_APTIVIO_SUMMARY_ACCESSED",
    "USER",
    (req) => String(req.params.clientId),
  ),
  getAdvisorClientAptivioSummary,
);

export default router;
''')

write("apps/api/src/modules/invitations/invitations.routes.ts", '''import { Router } from "express";
import type { NextFunction, Request, Response } from "express";

import { auditPrivilegedRequest } from "../../middleware/audit-privileged";
import {
  requireAdminRecentMfa,
  requireAuth,
  requireRecentMfa,
  requireRole,
} from "../../middleware/require-auth";
import { acceptInvitation, createInvitation, getInvitationByToken } from "./invitations.controller";

const router = Router();

function requireAdvisorOrAdminRecentMfa(req: Request, res: Response, next: NextFunction) {
  const roleCodes = new Set(req.auth?.roleCodes ?? []);

  if (roleCodes.has("admin") || roleCodes.has("auditor")) {
    return requireAdminRecentMfa()(req, res, next);
  }

  return requireRecentMfa()(req, res, next);
}

router.post(
  "/advisor/invitations",
  requireAuth,
  requireRole("advisor", "admin"),
  requireAdvisorOrAdminRecentMfa,
  auditPrivilegedRequest("INVITATION_CREATE_REQUESTED", "INVITATION"),
  createInvitation,
);

router.get("/invitations/:token", getInvitationByToken);
router.post("/invitations/:token/accept", requireAuth, acceptInvitation);

export default router;
''')

print("Patched Phase 1.6 files: security-audit helper, privileged audit middleware, MFA service/controller, and privileged routes.")
PY

echo "Phase 1.6 patch applied."
