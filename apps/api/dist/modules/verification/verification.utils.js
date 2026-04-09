"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.normalizeEmail = normalizeEmail;
exports.maskEmail = maskEmail;
exports.hashForStorage = hashForStorage;
exports.generateOtpCode = generateOtpCode;
exports.generateOpaqueToken = generateOpaqueToken;
exports.addMinutes = addMinutes;
const crypto_1 = __importDefault(require("crypto"));
const notifications_config_1 = require("../notifications/notifications.config");
function normalizeEmail(email) {
    return email.trim().toLowerCase();
}
function maskEmail(email) {
    const [local, domain] = normalizeEmail(email).split("@");
    if (!local || !domain)
        return email;
    const shown = local.length <= 2 ? local[0] ?? "*" : `${local.slice(0, 2)}***`;
    return `${shown}@${domain}`;
}
function hashForStorage(value) {
    return crypto_1.default
        .createHmac("sha256", notifications_config_1.notificationsConfig.otpHmacSecret)
        .update(value)
        .digest("hex");
}
function generateOtpCode() {
    return String(Math.floor(100000 + Math.random() * 900000));
}
function generateOpaqueToken() {
    return crypto_1.default.randomBytes(32).toString("hex");
}
function addMinutes(minutes) {
    return new Date(Date.now() + minutes * 60 * 1000);
}
