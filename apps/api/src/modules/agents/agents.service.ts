import { prisma } from "../../lib/prisma";
import { withTx } from "../../lib/service/tx";
import { writeAuditEvent } from "../../lib/service/audit";
import { parseDto } from "../../lib/service/zod";
import {
  createAgentDto,
  createAgentKeyDto,
  grantMandateDto,
} from "./agents.dto";
import {
  mapCreateAgentDto,
  mapCreateAgentKeyDto,
  mapGrantMandateDto,
} from "./agents.mappers";

export async function createAgent(userId: string, input: unknown) {
  const dto = parseDto(createAgentDto, input);

  return withTx(prisma, async (tx) => {
    const agent = await tx.agent.create({
      data: mapCreateAgentDto(userId, dto),
    });

    await writeAuditEvent(tx, {
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

export async function createAgentKey(userId: string, agentId: string, input: unknown) {
  const dto = parseDto(createAgentKeyDto, input);

  return withTx(prisma, async (tx) => {
    const key = await tx.agentKey.create({
      data: mapCreateAgentKeyDto(agentId, dto),
    });

    await writeAuditEvent(tx, {
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

export async function grantMandate(userId: string, agentId: string, input: unknown) {
  const dto = parseDto(grantMandateDto, input);

  return withTx(prisma, async (tx) => {
    const mandate = await tx.mandate.create({
      data: mapGrantMandateDto(agentId, dto),
    });

    await writeAuditEvent(tx, {
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
