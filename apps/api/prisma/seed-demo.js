const { PrismaClient } = require("@prisma/client");
const prisma = new PrismaClient();

async function main() {
  // Re-create the same userId you were seeing before wipe (so your existing cookies/JWTs may start working again)
  const id = process.env.SEED_USER_ID || "cmmcxp5sj0000n86w940l516v";

  // NOTE: adjust fields to match YOUR prisma/schema.prisma User model
  await prisma.user.upsert({
    where: { id },
    update: {},
    create: {
      id,
      email: "jes@dcapx.local",
      name: "jes",
      role: "ADMIN",
    },
  });

  console.log("Seeded user:", id);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
