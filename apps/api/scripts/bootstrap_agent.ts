import crypto from "crypto";
import fs from "node:fs";
import path from "node:path";
import { prisma } from "../src/infra/prisma";

// Adjust these if your Prisma schema differs:
const DEMO_USERNAME = "demo";
const DEMO_EMAIL = "demo@dcapx.local";

async function main() {
  // 1) Ensure secrets dir exists
  const secretsDir = path.resolve(process.cwd(), "secrets");
  fs.mkdirSync(secretsDir, { recursive: true });

  // 2) Ensure demo user exists
  let user = await prisma.user.findUnique({ where: { username: DEMO_USERNAME } });
  if (!user) {
    user = await prisma.user.create({
      data: {
        username: DEMO_USERNAME,
        email: DEMO_EMAIL,
        passwordHash: "DEV_SEED_ONLY_DO_NOT_USE_IN_PROD",
        totpSecret: null,
      } as any,
    });
  }

  // 3) Create agent + keypair
  const { publicKey, privateKey } = crypto.generateKeyPairSync("ed25519");
  const publicKeyPem = publicKey.export({ format: "pem", type: "spki" }).toString("utf8");
  const privateKeyPem = privateKey.export({ format: "pem", type: "pkcs8" }).toString("utf8");

  const agent = await prisma.agent.create({
    data: {
      userId: user.id,
      name: "Bootstrap Agent",
      kind: "MARKET_MAKER",        // must match your Agent.kind enum
      status: "ACTIVE",
      version: "1.0",
      aptivioTokenId: null,
      config: { notes: "bootstrapped for local signing test" },
      keys: {
        create: { publicKeyPem },
      },
    } as any,
    include: { keys: true },
  });

  const pemPath = path.join(secretsDir, `agent_${agent.id}_private.pem`);
  fs.writeFileSync(pemPath, privateKeyPem, "utf8");

  console.log("✅ Bootstrapped agent:");
  console.log("AGENT_ID=", agent.id);
  console.log("PRIVATE_KEY_PATH=", pemPath);
  console.log("PUBLIC_KEY_PEM=\n", publicKeyPem);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
