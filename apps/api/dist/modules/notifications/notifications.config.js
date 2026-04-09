"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.notificationsConfig = void 0;
const isProduction = process.env.NODE_ENV === "production";
function requireEnv(name) {
    const value = process.env[name]?.trim();
    if (!value) {
        throw new Error(`${name} is required`);
    }
    return value;
}
const emailProvider = (process.env.EMAIL_PROVIDER ??
    (isProduction ? "resend" : process.env.RESEND_API_KEY ? "resend" : "console"));
if (isProduction && emailProvider === "console") {
    throw new Error("EMAIL_PROVIDER=console is not allowed in production");
}
exports.notificationsConfig = {
    appBaseUrl: process.env.APP_BASE_URL ?? "http://localhost:3002",
    emailProvider,
    emailFrom: isProduction
        ? requireEnv("EMAIL_FROM")
        : process.env.EMAIL_FROM ?? "DCapX <no-reply@dcapitalx.local>",
    resendApiKey: process.env.RESEND_API_KEY ?? "",
    otpHmacSecret: isProduction
        ? requireEnv("OTP_HMAC_SECRET")
        : process.env.OTP_HMAC_SECRET ?? "local-dev-only-otp-secret-change-me",
    verificationOtpMinutes: Number(process.env.VERIFICATION_OTP_MINUTES ?? 10),
    resetLinkMinutes: Number(process.env.RESET_LINK_MINUTES ?? 30),
};
