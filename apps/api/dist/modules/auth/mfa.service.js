"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.mfaService = void 0;
const crypto_1 = __importDefault(require("crypto"));
const otplib_1 = require("otplib");
const api_error_1 = require("../../lib/errors/api-error");
const prisma_1 = require("../../lib/prisma");
const security_audit_1 = require("../../lib/service/security-audit");
otplib_1.authenticator.options = {
    step: 30,
    window: 1,
};
class MfaService {
    async beginTotpEnrollment(userId, input, auditContext = {}) {
        const user = await prisma_1.prisma.user.findUnique({
            where: { id: userId },
            select: { id: true, email: true, username: true },
        });
        if (!user) {
            throw new api_error_1.ApiError({
                statusCode: 404,
                code: "USER_NOT_FOUND",
                message: "User not found.",
            });
        }
        const activeFactor = await prisma_1.prisma.mfaFactor.findFirst({
            where: {
                userId,
                type: "TOTP",
                status: "ACTIVE",
                revokedAt: null,
            },
            orderBy: { createdAt: "desc" },
        });
        if (activeFactor) {
            throw new api_error_1.ApiError({
                statusCode: 409,
                code: "MFA_TOTP_ALREADY_ACTIVE",
                message: "A TOTP factor is already active for this account.",
            });
        }
        await prisma_1.prisma.mfaFactor.updateMany({
            where: { userId, type: "TOTP", status: "PENDING" },
            data: { status: "REVOKED", revokedAt: new Date() },
        });
        const secret = otplib_1.authenticator.generateSecret();
        const secretEncrypted = this.encryptSecret(secret);
        const factor = await prisma_1.prisma.mfaFactor.create({
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
        const otpauthUrl = otplib_1.authenticator.keyuri(accountName, issuer, secret);
        await (0, security_audit_1.recordSecurityAudit)({
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
    async activateTotpEnrollment(userId, sessionId, input, auditContext = {}) {
        const factorId = input.factorId?.trim();
        const token = input.token?.trim();
        if (!factorId || !token) {
            throw new api_error_1.ApiError({
                statusCode: 400,
                code: "MFA_TOTP_ACTIVATION_INVALID_INPUT",
                message: "factorId and token are required.",
            });
        }
        const factor = await prisma_1.prisma.mfaFactor.findFirst({
            where: { id: factorId, userId, type: "TOTP", status: "PENDING" },
        });
        if (!factor) {
            throw new api_error_1.ApiError({
                statusCode: 404,
                code: "MFA_TOTP_FACTOR_NOT_FOUND",
                message: "Pending TOTP factor not found.",
            });
        }
        const secret = this.decryptSecret(factor.secretEncrypted);
        const valid = otplib_1.authenticator.check(token, secret);
        if (!valid) {
            throw new api_error_1.ApiError({
                statusCode: 400,
                code: "MFA_TOTP_INVALID_TOKEN",
                message: "The provided TOTP code is invalid.",
            });
        }
        const now = new Date();
        let revokedOtherSessions = 0;
        await prisma_1.prisma.$transaction(async (tx) => {
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
            }
            else {
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
        await (0, security_audit_1.recordSecurityAudit)({
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
            await (0, security_audit_1.recordSecurityAudit)({
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
    async challengeTotp(userId, sessionId, input, auditContext = {}) {
        const token = input.token?.trim();
        if (!token) {
            throw new api_error_1.ApiError({
                statusCode: 400,
                code: "MFA_TOTP_TOKEN_REQUIRED",
                message: "A TOTP token is required.",
            });
        }
        if (!sessionId) {
            throw new api_error_1.ApiError({
                statusCode: 401,
                code: "UNAUTHENTICATED",
                message: "Authentication required.",
            });
        }
        const factor = await prisma_1.prisma.mfaFactor.findFirst({
            where: {
                userId,
                type: "TOTP",
                status: "ACTIVE",
                revokedAt: null,
            },
            orderBy: { activatedAt: "desc" },
        });
        if (!factor) {
            throw new api_error_1.ApiError({
                statusCode: 404,
                code: "MFA_TOTP_NOT_ENROLLED",
                message: "No active TOTP factor was found for this account.",
            });
        }
        const secret = this.decryptSecret(factor.secretEncrypted);
        const valid = otplib_1.authenticator.check(token, secret);
        if (!valid) {
            throw new api_error_1.ApiError({
                statusCode: 400,
                code: "MFA_TOTP_INVALID_TOKEN",
                message: "The provided TOTP code is invalid.",
            });
        }
        const now = new Date();
        await prisma_1.prisma.session.update({
            where: { id: sessionId },
            data: {
                mfaMethod: "TOTP",
                mfaVerifiedAt: now,
            },
        });
        await (0, security_audit_1.recordSecurityAudit)({
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
    async regenerateRecoveryCodes(userId, sessionId, input = {}, auditContext = {}) {
        const activeFactor = await prisma_1.prisma.mfaFactor.findFirst({
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
            throw new api_error_1.ApiError({
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
        await prisma_1.prisma.$transaction(async (tx) => {
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
            }
            else {
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
        await (0, security_audit_1.recordSecurityAudit)({
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
            await (0, security_audit_1.recordSecurityAudit)({
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
    async challengeRecoveryCode(userId, sessionId, input, auditContext = {}) {
        const code = input.code?.trim();
        if (!code) {
            throw new api_error_1.ApiError({
                statusCode: 400,
                code: "MFA_RECOVERY_CODE_REQUIRED",
                message: "A recovery code is required.",
            });
        }
        if (!sessionId) {
            throw new api_error_1.ApiError({
                statusCode: 401,
                code: "UNAUTHENTICATED",
                message: "Authentication required.",
            });
        }
        const codeHash = this.hashRecoveryCode(code);
        const record = await prisma_1.prisma.mfaRecoveryCode.findFirst({
            where: {
                userId,
                codeHash,
                consumedAt: null,
            },
            orderBy: { createdAt: "desc" },
        });
        if (!record) {
            throw new api_error_1.ApiError({
                statusCode: 400,
                code: "MFA_RECOVERY_CODE_INVALID",
                message: "The provided recovery code is invalid.",
            });
        }
        const now = new Date();
        await prisma_1.prisma.$transaction([
            prisma_1.prisma.mfaRecoveryCode.update({
                where: { id: record.id },
                data: { consumedAt: now },
            }),
            prisma_1.prisma.session.update({
                where: { id: sessionId },
                data: {
                    mfaMethod: "RECOVERY_CODE",
                    mfaVerifiedAt: now,
                },
            }),
        ]);
        await (0, security_audit_1.recordSecurityAudit)({
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
    encryptSecret(secret) {
        const key = this.deriveKey();
        const iv = crypto_1.default.randomBytes(12);
        const cipher = crypto_1.default.createCipheriv("aes-256-gcm", key, iv);
        const encrypted = Buffer.concat([cipher.update(secret, "utf8"), cipher.final()]);
        const tag = cipher.getAuthTag();
        return [iv.toString("base64"), tag.toString("base64"), encrypted.toString("base64")].join(".");
    }
    decryptSecret(secretEncrypted) {
        const [ivB64, tagB64, dataB64] = secretEncrypted.split(".");
        if (!ivB64 || !tagB64 || !dataB64) {
            throw new api_error_1.ApiError({
                statusCode: 500,
                code: "MFA_TOTP_SECRET_INVALID",
                message: "Stored TOTP secret is invalid.",
            });
        }
        const key = this.deriveKey();
        const decipher = crypto_1.default.createDecipheriv("aes-256-gcm", key, Buffer.from(ivB64, "base64"));
        decipher.setAuthTag(Buffer.from(tagB64, "base64"));
        const decrypted = Buffer.concat([
            decipher.update(Buffer.from(dataB64, "base64")),
            decipher.final(),
        ]);
        return decrypted.toString("utf8");
    }
    deriveKey() {
        const raw = process.env.MFA_TOTP_ENCRYPTION_KEY?.trim();
        if (!raw) {
            throw new api_error_1.ApiError({
                statusCode: 500,
                code: "MFA_TOTP_ENCRYPTION_KEY_MISSING",
                message: "MFA encryption key is not configured.",
            });
        }
        return crypto_1.default.createHash("sha256").update(raw).digest();
    }
    generateRecoveryCode() {
        let raw = "";
        while (raw.length < 12) {
            raw += crypto_1.default
                .randomBytes(8)
                .toString("base64url")
                .replace(/[^A-Za-z0-9]/g, "")
                .toUpperCase();
        }
        raw = raw.slice(0, 12);
        return `${raw.slice(0, 4)}-${raw.slice(4, 8)}-${raw.slice(8, 12)}`;
    }
    hashRecoveryCode(code) {
        const normalized = code.replace(/[^A-Za-z0-9]/g, "").toUpperCase();
        return crypto_1.default.createHash("sha256").update(normalized).digest("hex");
    }
}
exports.mfaService = new MfaService();
