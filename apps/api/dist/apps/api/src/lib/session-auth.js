"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.SESSION_COOKIE_NAME = void 0;
exports.createSessionSecret = createSessionSecret;
exports.hashSessionSecret = hashSessionSecret;
exports.verifySessionSecret = verifySessionSecret;
exports.buildSessionCookieValue = buildSessionCookieValue;
exports.parseSessionCookieValue = parseSessionCookieValue;
exports.getCookieFromRequest = getCookieFromRequest;
exports.getSessionExpiryDate = getSessionExpiryDate;
exports.setSessionCookie = setSessionCookie;
exports.clearSessionCookie = clearSessionCookie;
const argon2_1 = __importDefault(require("argon2"));
const crypto_1 = __importDefault(require("crypto"));
exports.SESSION_COOKIE_NAME = "dcapx_session";
const SESSION_TTL_DAYS = 30;
function createSessionSecret() {
    return crypto_1.default.randomBytes(32).toString("hex");
}
async function hashSessionSecret(secret) {
    return argon2_1.default.hash(secret);
}
async function verifySessionSecret(hash, secret) {
    try {
        return await argon2_1.default.verify(hash, secret);
    }
    catch {
        return false;
    }
}
function buildSessionCookieValue(sessionId, secret) {
    return `${sessionId}.${secret}`;
}
function parseSessionCookieValue(value) {
    if (!value)
        return null;
    const firstDot = value.indexOf(".");
    if (firstDot <= 0)
        return null;
    const sessionId = value.slice(0, firstDot).trim();
    const secret = value.slice(firstDot + 1).trim();
    if (!sessionId || !secret)
        return null;
    return { sessionId, secret };
}
function getCookieFromRequest(req, name) {
    const raw = req.headers.cookie;
    if (!raw)
        return null;
    const parts = raw.split(";").map((part) => part.trim());
    for (const part of parts) {
        const eqIdx = part.indexOf("=");
        if (eqIdx === -1)
            continue;
        const key = part.slice(0, eqIdx).trim();
        const value = part.slice(eqIdx + 1).trim();
        if (key === name) {
            return decodeURIComponent(value);
        }
    }
    return null;
}
function getSessionExpiryDate() {
    const d = new Date();
    d.setDate(d.getDate() + SESSION_TTL_DAYS);
    return d;
}
function setSessionCookie(res, sessionCookieValue, expiresAt) {
    const isProduction = process.env.NODE_ENV === "production";
    res.setHeader("Set-Cookie", `${exports.SESSION_COOKIE_NAME}=${encodeURIComponent(sessionCookieValue)}; Path=/; HttpOnly; SameSite=Lax; ${isProduction ? "Secure; " : ""}Expires=${expiresAt.toUTCString()}`);
}
function clearSessionCookie(res) {
    const isProduction = process.env.NODE_ENV === "production";
    res.setHeader("Set-Cookie", `${exports.SESSION_COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Lax; ${isProduction ? "Secure; " : ""}Expires=Thu, 01 Jan 1970 00:00:00 GMT`);
}
