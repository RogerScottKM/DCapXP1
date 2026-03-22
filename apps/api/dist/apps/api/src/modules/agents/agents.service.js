"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createAgent = createAgent;
exports.createAgentKey = createAgentKey;
exports.grantMandate = grantMandate;
const prisma_1 = require("../../lib/prisma");
const tx_1 = require("../../lib/service/tx");
const audit_1 = require("../../lib/service/audit");
const zod_1 = require("../../lib/service/zod");
const agents_dto_1 = require("./agents.dto");
const agents_mappers_1 = require("./agents.mappers");
async function createAgent(userId, input) {
    const dto = (0, zod_1.parseDto)(agents_dto_1.createAgentDto, input);
    return (0, tx_1.withTx)(prisma_1.prisma, async (tx) => {
        const agent = await tx.agent.create({
            data: (0, agents_mappers_1.mapCreateAgentDto)(userId, dto),
        });
        await (0, audit_1.writeAuditEvent)(tx, {
            actorType: "USER",
            actorId: userId,
            action: "AGENT_CREATED",
            resourceType: "Agent",
            resourceId: agent.id,
            metadata: { kind: agent.kind, principalType: agent.principalType },
        });
        return agent;
    });
}
async function createAgentKey(userId, agentId, input) {
    const dto = (0, zod_1.parseDto)(agents_dto_1.createAgentKeyDto, input);
    return (0, tx_1.withTx)(prisma_1.prisma, async (tx) => {
        const key = await tx.agentKey.create({
            data: (0, agents_mappers_1.mapCreateAgentKeyDto)(agentId, dto),
        });
        await (0, audit_1.writeAuditEvent)(tx, {
            actorType: "USER",
            actorId: userId,
            action: "AGENT_KEY_CREATED",
            resourceType: "AgentKey",
            resourceId: key.id,
            metadata: { agentId, credentialType: key.credentialType },
        });
        return key;
    });
}
async function grantMandate(userId, agentId, input) {
    const dto = (0, zod_1.parseDto)(agents_dto_1.grantMandateDto, input);
    return (0, tx_1.withTx)(prisma_1.prisma, async (tx) => {
        const mandate = await tx.mandate.create({
            data: (0, agents_mappers_1.mapGrantMandateDto)(agentId, dto),
        });
        await (0, audit_1.writeAuditEvent)(tx, {
            actorType: "USER",
            actorId: userId,
            action: "AGENT_MANDATE_GRANTED",
            resourceType: "Mandate",
            resourceId: mandate.id,
            metadata: { agentId, action: mandate.action, market: mandate.market },
        });
        return mandate;
    });
}
