export type EmailProviderName = "console" | "resend";

export const notificationsConfig = {
  appBaseUrl: process.env.APP_BASE_URL ?? "http://localhost:3002",
  emailProvider: (process.env.EMAIL_PROVIDER ?? (process.env.RESEND_API_KEY ? "resend" : "console")) as EmailProviderName,
  emailFrom: process.env.EMAIL_FROM ?? "DCapX <no-reply@dcapitalx.local>",
  resendApiKey: process.env.RESEND_API_KEY ?? "",
  otpHmacSecret:
    process.env.OTP_HMAC_SECRET ??
    process.env.SESSION_SECRET ??
    process.env.JWT_SECRET ??
    "dev-only-change-me",
  verificationOtpMinutes: Number(process.env.VERIFICATION_OTP_MINUTES ?? 10),
  resetLinkMinutes: Number(process.env.RESET_LINK_MINUTES ?? 30),
};
