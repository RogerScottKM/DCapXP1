"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.verificationService = exports.VerificationService = void 0;
const argon2 = __importStar(require("argon2"));
const prisma_1 = require("../../lib/prisma");
const notification_service_1 = require("../notifications/notification.service");
const notifications_config_1 = require("../notifications/notifications.config");
const verification_utils_1 = require("./verification.utils");
const CONTACT_VERIFICATION_PURPOSE = "CONTACT_VERIFICATION";
class VerificationService {
    async requestEmailVerification(emailInput) {
        const email = (0, verification_utils_1.normalizeEmail)(emailInput);
        const user = await prisma_1.prisma.user.findFirst({
            where: { email },
        });
        if (!user) {
            return { ok: true, message: "If an account exists, a verification email has been sent." };
        }
        if (user.emailVerifiedAt) {
            return { ok: true, message: "Email already verified." };
        }
        await prisma_1.prisma.verificationChallenge.updateMany({
            where: {
                userId: user.id,
                channel: "EMAIL",
                purpose: CONTACT_VERIFICATION_PURPOSE,
                status: "PENDING",
            },
            data: {
                status: "CANCELLED",
            },
        });
        const code = (0, verification_utils_1.generateOtpCode)();
        const destinationHash = (0, verification_utils_1.hashForStorage)(email);
        const codeHash = (0, verification_utils_1.hashForStorage)(code);
        const challenge = await prisma_1.prisma.verificationChallenge.create({
            data: {
                userId: user.id,
                channel: "EMAIL",
                purpose: CONTACT_VERIFICATION_PURPOSE,
                destinationMasked: (0, verification_utils_1.maskEmail)(email),
                destinationHash,
                codeHash,
                expiresAt: (0, verification_utils_1.addMinutes)(notifications_config_1.notificationsConfig.verificationOtpMinutes),
                maxAttempts: 5,
                status: "PENDING",
            },
        });
        await notification_service_1.notificationService.sendVerificationOtpEmail({
            userId: user.id,
            to: email,
            code,
        });
        return {
            ok: true,
            message: "If an account exists, a verification email has been sent.",
            challengeId: challenge.id,
        };
    }
    async confirmEmailVerification(emailInput, codeInput) {
        const email = (0, verification_utils_1.normalizeEmail)(emailInput);
        const destinationHash = (0, verification_utils_1.hashForStorage)(email);
        const codeHash = (0, verification_utils_1.hashForStorage)(codeInput.trim());
        const challenge = await prisma_1.prisma.verificationChallenge.findFirst({
            where: {
                channel: "EMAIL",
                purpose: CONTACT_VERIFICATION_PURPOSE,
                destinationHash,
                status: "PENDING",
            },
            orderBy: { createdAt: "desc" },
        });
        if (!challenge) {
            throw new Error("Invalid or expired verification code.");
        }
        const now = new Date();
        if (challenge.expiresAt <= now) {
            await prisma_1.prisma.verificationChallenge.update({
                where: { id: challenge.id },
                data: { status: "EXPIRED" },
            });
            throw new Error("Invalid or expired verification code.");
        }
        if (challenge.attemptCount >= challenge.maxAttempts) {
            await prisma_1.prisma.verificationChallenge.update({
                where: { id: challenge.id },
                data: { status: "LOCKED" },
            });
            throw new Error("Too many verification attempts. Request a new code.");
        }
        if (challenge.codeHash !== codeHash) {
            const nextAttempts = challenge.attemptCount + 1;
            await prisma_1.prisma.verificationChallenge.update({
                where: { id: challenge.id },
                data: {
                    attemptCount: nextAttempts,
                    status: nextAttempts >= challenge.maxAttempts ? "LOCKED" : "PENDING",
                },
            });
            throw new Error("Invalid or expired verification code.");
        }
        await prisma_1.prisma.$transaction([
            prisma_1.prisma.verificationChallenge.update({
                where: { id: challenge.id },
                data: {
                    consumedAt: now,
                    status: "VERIFIED",
                },
            }),
            prisma_1.prisma.user.update({
                where: { id: challenge.userId },
                data: { emailVerifiedAt: now },
            }),
        ]);
        return { ok: true, message: "Email verified successfully." };
    }
    async requestPasswordReset(emailInput) {
        const email = (0, verification_utils_1.normalizeEmail)(emailInput);
        const user = await prisma_1.prisma.user.findFirst({
            where: { email },
        });
        if (!user) {
            return { ok: true, message: "If an account exists, a reset email has been sent." };
        }
        await prisma_1.prisma.verificationChallenge.updateMany({
            where: {
                userId: user.id,
                channel: "EMAIL",
                purpose: "PASSWORD_RESET",
                status: "PENDING",
            },
            data: {
                status: "CANCELLED",
            },
        });
        const token = (0, verification_utils_1.generateOpaqueToken)();
        const destinationHash = (0, verification_utils_1.hashForStorage)(email);
        const codeHash = (0, verification_utils_1.hashForStorage)(token);
        const challenge = await prisma_1.prisma.verificationChallenge.create({
            data: {
                userId: user.id,
                channel: "EMAIL",
                purpose: "PASSWORD_RESET",
                destinationMasked: (0, verification_utils_1.maskEmail)(email),
                destinationHash,
                codeHash,
                expiresAt: (0, verification_utils_1.addMinutes)(notifications_config_1.notificationsConfig.resetLinkMinutes),
                maxAttempts: 5,
                status: "PENDING",
            },
        });
        const resetUrl = `${notifications_config_1.notificationsConfig.appBaseUrl}/reset-password?token=${encodeURIComponent(token)}`;
        await notification_service_1.notificationService.sendPasswordResetEmail({
            userId: user.id,
            to: email,
            resetUrl,
        });
        return {
            ok: true,
            message: "If an account exists, a reset email has been sent.",
            challengeId: challenge.id,
        };
    }
    async resetPassword(tokenInput, password) {
        const codeHash = (0, verification_utils_1.hashForStorage)(tokenInput.trim());
        const challenge = await prisma_1.prisma.verificationChallenge.findFirst({
            where: {
                channel: "EMAIL",
                purpose: "PASSWORD_RESET",
                codeHash,
                status: "PENDING",
            },
            orderBy: { createdAt: "desc" },
        });
        if (!challenge) {
            throw new Error("Invalid or expired reset token.");
        }
        const now = new Date();
        if (challenge.expiresAt <= now) {
            await prisma_1.prisma.verificationChallenge.update({
                where: { id: challenge.id },
                data: { status: "EXPIRED" },
            });
            throw new Error("Invalid or expired reset token.");
        }
        const newPasswordHash = await argon2.hash(password);
        await prisma_1.prisma.$transaction([
            prisma_1.prisma.verificationChallenge.update({
                where: { id: challenge.id },
                data: {
                    consumedAt: now,
                    status: "VERIFIED",
                },
            }),
            prisma_1.prisma.user.update({
                where: { id: challenge.userId },
                data: { passwordHash: newPasswordHash },
            }),
        ]);
        return { ok: true, message: "Password reset successfully." };
    }
}
exports.VerificationService = VerificationService;
exports.verificationService = new VerificationService();
