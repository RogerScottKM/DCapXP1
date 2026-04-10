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
