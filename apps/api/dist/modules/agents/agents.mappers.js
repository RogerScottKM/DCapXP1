"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.mapCreateAgentDto = mapCreateAgentDto;
exports.mapCreateAgentKeyDto = mapCreateAgentKeyDto;
exports.mapGrantMandateDto = mapGrantMandateDto;
const prisma_json_1 = require("../../lib/prisma-json");
function mapCreateAgentDto(userId, dto) {
    return {
        user: { connect: { id: userId } },
        name: dto.name,
        principalType: dto.principalType,
        kind: dto.kind,
        capabilityTier: dto.capabilityTier,
        version: dto.version ?? "1.0",
        config: (0, prisma_json_1.asJson)(dto.config),
        aptivioTokenId: dto.aptivioTokenId,
        status: "DRAFT",
    };
}
function mapCreateAgentKeyDto(agentId, dto) {
    return {
        agent: { connect: { id: agentId } },
        credentialType: dto.credentialType,
        publicKeyPem: dto.credentialType === "PUBLIC_KEY" ? dto.publicKeyPem : undefined,
        keyPrefix: dto.credentialType === "API_KEY" ? dto.keyPrefix : undefined,
        keyHash: dto.credentialType === "API_KEY" ? dto.keyHash : undefined,
        expiresAt: dto.expiresAt ? new Date(dto.expiresAt) : undefined,
    };
}
function mapGrantMandateDto(agentId, dto) {
    return {
        agent: { connect: { id: agentId } },
        action: dto.action,
        market: dto.market,
        maxNotionalPerDay: BigInt(dto.maxNotionalPerDay),
        maxOrdersPerDay: dto.maxOrdersPerDay,
        notBefore: dto.notBefore ? new Date(dto.notBefore) : undefined,
        expiresAt: new Date(dto.expiresAt),
        constraints: (0, prisma_json_1.asJson)(dto.constraints),
        mandateJwtHash: dto.mandateJwtHash,
        status: "ACTIVE",
    };
}
