"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateInvitationToken = generateInvitationToken;
exports.hashInvitationToken = hashInvitationToken;
const crypto_1 = __importDefault(require("crypto"));
function generateInvitationToken() { return crypto_1.default.randomBytes(32).toString("hex"); }
function hashInvitationToken(rawToken) { return crypto_1.default.createHash("sha256").update(rawToken).digest("hex"); }
