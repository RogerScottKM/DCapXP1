"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerUser = registerUser;
const argon2_1 = __importDefault(require("argon2"));
const prisma_1 = require("../../lib/prisma");
const tx_1 = require("../../lib/service/tx");
const audit_1 = require("../../lib/service/audit");
const zod_1 = require("../../lib/service/zod");
const auth_dto_1 = require("./auth.dto");
const auth_mappers_1 = require("./auth.mappers");
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
