import crypto from "crypto";
import { notificationsConfig } from "../notifications/notifications.config";

export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

export function maskEmail(email: string): string {
  const [local, domain] = normalizeEmail(email).split("@");
  if (!local || !domain) return email;
  const shown = local.length <= 2 ? local[0] ?? "*" : `${local.slice(0, 2)}***`;
  return `${shown}@${domain}`;
}

export function hashForStorage(value: string): string {
  return crypto
    .createHmac("sha256", notificationsConfig.otpHmacSecret)
    .update(value)
    .digest("hex");
}

export function generateOtpCode(): string {
  return String(Math.floor(100000 + Math.random() * 900000));
}

export function generateOpaqueToken(): string {
  return crypto.randomBytes(32).toString("hex");
}

export function addMinutes(minutes: number): Date {
  return new Date(Date.now() + minutes * 60 * 1000);
}
