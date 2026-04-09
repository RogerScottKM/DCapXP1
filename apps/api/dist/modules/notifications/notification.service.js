"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.notificationService = exports.NotificationService = void 0;
const prisma_1 = require("../../lib/prisma");
const notifications_config_1 = require("./notifications.config");
const console_email_provider_1 = require("./providers/console-email.provider");
const resend_email_provider_1 = require("./providers/resend-email.provider");
function maskEmail(email) {
    const [local, domain] = email.trim().toLowerCase().split("@");
    if (!local || !domain)
        return email;
    const shown = local.length <= 2 ? (local[0] ?? "*") : `${local.slice(0, 2)}***`;
    return `${shown}@${domain}`;
}
function getEmailProvider() {
    if (notifications_config_1.notificationsConfig.emailProvider === "resend") {
        if (!notifications_config_1.notificationsConfig.resendApiKey) {
            throw new Error("RESEND_API_KEY is required when EMAIL_PROVIDER=resend");
        }
        return new resend_email_provider_1.ResendEmailProvider(notifications_config_1.notificationsConfig.resendApiKey, notifications_config_1.notificationsConfig.emailFrom);
    }
    return new console_email_provider_1.ConsoleEmailProvider();
}
class NotificationService {
    emailProvider = getEmailProvider();
    async sendVerificationOtpEmail(args) {
        const subject = "Verify your DCapX email";
        const html = `
      <div style="font-family:Arial,sans-serif;line-height:1.5">
        <h2>Verify your DCapX email</h2>
        <p>Your verification code is:</p>
        <p style="font-size:28px;font-weight:700;letter-spacing:4px">${args.code}</p>
        <p>This code expires in ${notifications_config_1.notificationsConfig.verificationOtpMinutes} minutes.</p>
      </div>
    `;
        const text = `Your DCapX verification code is ${args.code}. It expires in ${notifications_config_1.notificationsConfig.verificationOtpMinutes} minutes.`;
        let provider = String(notifications_config_1.notificationsConfig.emailProvider);
        let providerMessageId = null;
        let status = "SENT";
        let errorCode = null;
        let errorMessage = null;
        try {
            const result = await this.emailProvider.send({
                to: args.to,
                subject,
                html,
                text,
            });
            provider = result.provider;
            providerMessageId = result.providerMessageId ?? null;
        }
        catch (error) {
            status = "FAILED";
            errorCode = "EMAIL_SEND_FAILED";
            errorMessage = error?.message ?? "Unknown email provider error";
            throw error;
        }
        finally {
            await prisma_1.prisma.notificationDelivery.create({
                data: {
                    userId: args.userId,
                    channel: "EMAIL",
                    templateKey: "VERIFY_EMAIL_OTP",
                    provider,
                    destinationMasked: maskEmail(args.to),
                    providerMessageId,
                    status,
                    errorCode,
                    errorMessage,
                },
            });
        }
    }
    async sendPasswordResetEmail(args) {
        const subject = "Reset your DCapX password";
        const html = `
      <div style="font-family:Arial,sans-serif;line-height:1.5">
        <h2>Reset your DCapX password</h2>
        <p>Use the link below to reset your password:</p>
        <p><a href="${args.resetUrl}">${args.resetUrl}</a></p>
        <p>This link expires in ${notifications_config_1.notificationsConfig.resetLinkMinutes} minutes.</p>
      </div>
    `;
        const text = `Reset your DCapX password using this link: ${args.resetUrl}. It expires in ${notifications_config_1.notificationsConfig.resetLinkMinutes} minutes.`;
        let provider = String(notifications_config_1.notificationsConfig.emailProvider);
        let providerMessageId = null;
        let status = "SENT";
        let errorCode = null;
        let errorMessage = null;
        try {
            const result = await this.emailProvider.send({
                to: args.to,
                subject,
                html,
                text,
            });
            provider = result.provider;
            providerMessageId = result.providerMessageId ?? null;
        }
        catch (error) {
            status = "FAILED";
            errorCode = "EMAIL_SEND_FAILED";
            errorMessage = error?.message ?? "Unknown email provider error";
            throw error;
        }
        finally {
            await prisma_1.prisma.notificationDelivery.create({
                data: {
                    userId: args.userId,
                    channel: "EMAIL",
                    templateKey: "PASSWORD_RESET",
                    provider,
                    destinationMasked: maskEmail(args.to),
                    providerMessageId,
                    status,
                    errorCode,
                    errorMessage,
                },
            });
        }
    }
}
exports.NotificationService = NotificationService;
exports.notificationService = new NotificationService();
