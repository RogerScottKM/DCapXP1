"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.authService = void 0;
exports.registerUser = registerUser;
const argon2_1 = __importDefault(require("argon2"));
const prisma_1 = require("../../lib/prisma");
const tx_1 = require("../../lib/service/tx");
const audit_1 = require("../../lib/service/audit");
const zod_1 = require("../../lib/service/zod");
const auth_dto_1 = require("./auth.dto");
const auth_mappers_1 = require("./auth.mappers");
const api_error_1 = require("../../lib/errors/api-error");
const session_auth_1 = require("../../lib/session-auth");
async function registerUser(input) {
    const dto = (0, zod_1.parseDto)(auth_dto_1.registerDto, input);
    const passwordHash = await argon2_1.default.hash("temporary-password-to-be-reset");
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
            throw new api_error_1.ApiError({
                statusCode: 401,
                code: "LOGIN_INVALID_CREDENTIALS",
                message: "Invalid credentials.",
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
            include: {
                profile: true,
                roles: true,
            },
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
    async resolveAuthFromRequest(req) {
        const rawCookie = (0, session_auth_1.getCookieFromRequest)(req, session_auth_1.SESSION_COOKIE_NAME);
        const parsed = (0, session_auth_1.parseSessionCookieValue)(rawCookie);
        if (!parsed)
            return null;
        const session = await prisma_1.prisma.session.findUnique({
            where: { id: parsed.sessionId },
        });
        if (!session)
            return null;
        if (session.revokedAt)
            return null;
        if (session.expiresAt.getTime() <= Date.now())
            return null;
        const secretOk = await (0, session_auth_1.verifySessionSecret)(session.refreshTokenHash, parsed.secret);
        if (!secretOk)
            return null;
        return {
            userId: session.userId,
            sessionId: session.id,
        };
    }
    getRequestIp(req) {
        const xff = req.headers["x-forwarded-for"];
        if (typeof xff === "string" && xff.length > 0) {
            return xff.split(",")[0].trim();
        }
        return req.socket.remoteAddress ?? null;
    }
}
exports.authService = new AuthService();
