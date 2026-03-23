import argon2 from "argon2";
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

export async function registerUser(input: unknown) {
  const dto = parseDto(registerDto, input);

  const passwordHash = await argon2.hash("temporary-password-to-be-reset");

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
        OR: [
          { email: identifier.toLowerCase() },
          { username: identifier },
        ],
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
      include: {
        profile: true,
        roles: true,
      },
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
            }
          : null,
        roles: user.roles.map((role) => ({
          roleCode: role.roleCode,
          scopeType: role.scopeType,
          scopeId: role.scopeId,
        })),
      },
      session: {
        id: auth.sessionId,
      },
    };
  }

  async logout(req: Request, res: Response) {
    const parsed = parseSessionCookieValue(
      getCookieFromRequest(req, SESSION_COOKIE_NAME)
    );

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

  async resolveAuthFromRequest(
    req: Request
  ): Promise<{ userId: string; sessionId: string } | null> {
    const rawCookie = getCookieFromRequest(req, SESSION_COOKIE_NAME);
    const parsed = parseSessionCookieValue(rawCookie);

    if (!parsed) return null;

    const session = await prisma.session.findUnique({
      where: { id: parsed.sessionId },
    });

    if (!session) return null;
    if (session.revokedAt) return null;
    if (session.expiresAt.getTime() <= Date.now()) return null;

    const secretOk = await verifySessionSecret(
      session.refreshTokenHash,
      parsed.secret
    );

    if (!secretOk) return null;

    return {
      userId: session.userId,
      sessionId: session.id,
    };
  }

  private getRequestIp(req: Request): string | null {
    const xff = req.headers["x-forwarded-for"];
    if (typeof xff === "string" && xff.length > 0) {
      return xff.split(",")[0].trim();
    }
    return req.socket.remoteAddress ?? null;
  }
}

export const authService = new AuthService();
