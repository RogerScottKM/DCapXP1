"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.authService = void 0;
exports.registerUser = registerUser;
const argon2_1 = __importDefault(require("argon2"));
const crypto_1 = __importDefault(require("crypto"));
const prisma_1 = require("../../lib/prisma");
const tx_1 = require("../../lib/service/tx");
const audit_1 = require("../../lib/service/audit");
const zod_1 = require("../../lib/service/zod");
const auth_dto_1 = require("./auth.dto");
const auth_mappers_1 = require("./auth.mappers");
const api_error_1 = require("../../lib/errors/api-error");
const session_auth_1 = require("../../lib/session-auth");
const verification_service_1 = require("../verification/verification.service");
async function registerUser(input) {
    const dto = (0, zod_1.parseDto)(auth_dto_1.registerDto, input);
    const passwordHash = await argon2_1.default.hash(crypto_1.default.randomBytes(32).toString("hex"));
    return (0, tx_1.withTx)(prisma_1.prisma, async (tx) => {
        const user = await tx.user.create({
            data: (0, auth_mappers_1.mapRegisterDtoToUserCreate)(dto, passwordHash),
            include: { profile: true },
        });
        await (0, audit_1.writeAuditEvent)(tx, {
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
class AuthService {
    async login(req, res, body) {
        const identifier = body?.identifier?.trim();
        const password = body?.password;
        if (!identifier || !password) {
            throw new api_error_1.ApiError({
                statusCode: 400,
                code: "LOGIN_INVALID_INPUT",
                message: "Identifier and password are required.",
                fieldErrors: {
                    ...(identifier ? {} : { identifier: "Required" }),
                    ...(password ? {} : { password: "Required" }),
                },
            });
        }
        const user = await prisma_1.prisma.user.findFirst({
            where: {
                OR: [{ email: identifier.toLowerCase() }, { username: identifier }],
            },
            include: {
                profile: true,
                roles: true,
            },
        });
        if (!user) {
            throw new api_error_1.ApiError({
                statusCode: 401,
                code: "LOGIN_INVALID_CREDENTIALS",
                message: "Invalid credentials.",
            });
        }
        if (user.status === "SUSPENDED" || user.status === "CLOSED") {
            throw new api_error_1.ApiError({
                statusCode: 403,
                code: "ACCOUNT_UNAVAILABLE",
                message: "This account is not available for sign-in.",
            });
        }
        const passwordOk = await argon2_1.default.verify(user.passwordHash, password);
        if (!passwordOk) {
            throw new api_error_1.ApiError({
                statusCode: 401,
                code: "LOGIN_INVALID_CREDENTIALS",
                message: "Invalid credentials.",
            });
        }
        const secret = (0, session_auth_1.createSessionSecret)();
        const refreshTokenHash = await (0, session_auth_1.hashSessionSecret)(secret);
        const expiresAt = (0, session_auth_1.getSessionExpiryDate)();
        const session = await prisma_1.prisma.session.create({
            data: {
                userId: user.id,
                refreshTokenHash,
                expiresAt,
                ipAddress: this.getRequestIp(req),
                userAgent: req.headers["user-agent"]?.toString() ?? null,
            },
        });
        const cookieValue = (0, session_auth_1.buildSessionCookieValue)(session.id, secret);
        (0, session_auth_1.setSessionCookie)(res, cookieValue, expiresAt);
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
    async getSession(req) {
        const auth = await this.resolveAuthFromRequest(req);
        if (!auth) {
            throw new api_error_1.ApiError({
                statusCode: 401,
                code: "UNAUTHENTICATED",
                message: "Authentication required.",
            });
        }
        const user = await prisma_1.prisma.user.findUnique({
            where: { id: auth.userId },
            include: { profile: true, roles: true },
        });
        if (!user) {
            throw new api_error_1.ApiError({
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
    async logout(req, res) {
        const parsed = (0, session_auth_1.parseSessionCookieValue)((0, session_auth_1.getCookieFromRequest)(req, session_auth_1.SESSION_COOKIE_NAME));
        if (parsed?.sessionId) {
            await prisma_1.prisma.session.updateMany({
                where: {
                    id: parsed.sessionId,
                    revokedAt: null,
                },
                data: {
                    revokedAt: new Date(),
                },
            });
        }
        (0, session_auth_1.clearSessionCookie)(res);
        return { ok: true };
    }
    async requestPasswordReset(body) {
        const email = body?.email?.trim().toLowerCase();
        if (!email) {
            throw new api_error_1.ApiError({
                statusCode: 400,
                code: "PASSWORD_RESET_EMAIL_REQUIRED",
                message: "Email is required.",
            });
        }
        return verification_service_1.verificationService.requestPasswordReset(email);
    }
    async resetPassword(body) {
        const token = body?.token?.trim();
        const newPassword = body?.newPassword;
        if (!token || !newPassword) {
            throw new api_error_1.ApiError({
                statusCode: 400,
                code: "PASSWORD_RESET_INVALID_INPUT",
                message: "Token and new password are required.",
            });
        }
        if (newPassword.length < 10) {
            throw new api_error_1.ApiError({
                statusCode: 400,
                code: "PASSWORD_TOO_SHORT",
                message: "Password must be at least 10 characters long.",
            });
        }
        return verification_service_1.verificationService.resetPassword(token, newPassword);
    }
    async sendOtp(userId, body) {
        const channel = body?.channel || "EMAIL";
        const user = await prisma_1.prisma.user.findUnique({
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
            throw new api_error_1.ApiError({
                statusCode: 404,
                code: "USER_NOT_FOUND",
                message: "User not found.",
            });
        }
        const destination = channel === "EMAIL" ? user.email : user.phone;
        if (!destination) {
            throw new api_error_1.ApiError({
                statusCode: 400,
                code: "OTP_DESTINATION_MISSING",
                message: channel === "EMAIL"
                    ? "No email is available for this account."
                    : "No phone number is available for this account.",
            });
        }
        const now = new Date();
        await prisma_1.prisma.verificationCode.updateMany({
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
        await prisma_1.prisma.verificationCode.create({
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
            message: channel === "EMAIL"
                ? "A verification code has been sent to your email."
                : "A verification code has been sent to your phone.",
            channel,
            destinationMasked: this.maskDestination(destination, channel),
            expiresAtUtc: expiresAt.toISOString(),
            ...(process.env.NODE_ENV !== "production" ? { devOtpCode: code } : {}),
        };
    }
    async verifyOtp(userId, body) {
        const channel = body?.channel || "EMAIL";
        const code = body?.code?.trim();
        if (!code) {
            throw new api_error_1.ApiError({
                statusCode: 400,
                code: "OTP_CODE_REQUIRED",
                message: "Verification code is required.",
            });
        }
        const record = await prisma_1.prisma.verificationCode.findFirst({
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
            throw new api_error_1.ApiError({
                statusCode: 400,
                code: "OTP_INVALID",
                message: "This verification code is invalid or has expired.",
            });
        }
        const codeHash = this.hashVerificationCode(code);
        if (codeHash !== record.codeHash) {
            throw new api_error_1.ApiError({
                statusCode: 400,
                code: "OTP_INVALID",
                message: "This verification code is invalid or has expired.",
            });
        }
        const now = new Date();
        const [updatedUser] = await prisma_1.prisma.$transaction([
            prisma_1.prisma.user.update({
                where: { id: userId },
                data: channel === "EMAIL" ? { emailVerifiedAt: now } : { phoneVerifiedAt: now },
                select: { emailVerifiedAt: true, phoneVerifiedAt: true },
            }),
            prisma_1.prisma.verificationCode.update({
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
    async resolveAuthFromRequest(req) {
        const rawCookie = (0, session_auth_1.getCookieFromRequest)(req, session_auth_1.SESSION_COOKIE_NAME);
        const parsed = (0, session_auth_1.parseSessionCookieValue)(rawCookie);
        if (!parsed)
            return null;
        const session = await prisma_1.prisma.session.findUnique({
            where: { id: parsed.sessionId },
            include: { user: true },
        });
        if (!session)
            return null;
        if (session.revokedAt)
            return null;
        if (session.expiresAt.getTime() <= Date.now())
            return null;
        if (session.user.status === "SUSPENDED" || session.user.status === "CLOSED")
            return null;
        const secretOk = await (0, session_auth_1.verifySessionSecret)(session.refreshTokenHash, parsed.secret);
        if (!secretOk)
            return null;
        return { userId: session.userId, sessionId: session.id };
    }
    getRequestIp(req) {
        const xff = req.headers["x-forwarded-for"];
        if (typeof xff === "string" && xff.length > 0) {
            return xff.split(",")[0].trim();
        }
        return req.socket.remoteAddress ?? null;
    }
    hashVerificationCode(code) {
        return crypto_1.default.createHash("sha256").update(code).digest("hex");
    }
    generateOtpCode() {
        return String(Math.floor(100000 + Math.random() * 900000));
    }
    maskDestination(destination, channel) {
        if (channel === "EMAIL") {
            const [local, domain] = destination.split("@");
            if (!local || !domain)
                return destination;
            return `${local.slice(0, 2)}***@${domain}`;
        }
        return destination.length > 4 ? `***${destination.slice(-4)}` : destination;
    }
}
exports.authService = new AuthService();
