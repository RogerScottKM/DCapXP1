// apps/api/scripts/bootstrap_mandate.ts
import { prisma } from "../src/infra/prisma"; // <-- if you don't have this, use "../src/prisma"

async function main() {
  const agentId = process.env.AGENT_ID!;
  const market = process.env.MARKET ?? null; // null = allow all markets, or set "RVAI-USD"

  if (!agentId) throw new Error("Missing AGENT_ID");

  const agent = await prisma.agent.findUnique({
    where: { id: agentId },
  });
  if (!agent) throw new Error(`Agent not found: ${agentId}`);

  const now = new Date();

  const mandate = await prisma.mandate.create({
    data: {
      agentId: agent.id,
      action: "TRADE",
      status: "ACTIVE",
      revokedAt: null,

      // Make it valid immediately
      notBefore: new Date(now.getTime() - 60_000),
      expiresAt: new Date(now.getTime() + 365 * 24 * 60 * 60 * 1000),

      // Optional restrictions
      market, // set to "RVAI-USD" OR null

      // Keep it open for dev
      maxOrdersPerDay: 0, // 0 => unlimited (per your middleware logic)
      // If your schema has this field and it's BigInt:
      // maxNotionalPerDay: BigInt(0),
    },
  });

  console.log("✅ Mandate created:");
  console.log("MANDATE_ID=", mandate.id);
  console.log("AGENT_ID=", agentId);
  console.log("MARKET=", market ?? "(ALL)");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
