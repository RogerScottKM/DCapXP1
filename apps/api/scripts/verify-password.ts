import argon2 from "argon2";
import { prisma } from "../src/lib/prisma";

async function main() {
  const email = process.argv[2];
  const password = process.argv[3];

  if (!email || !password) {
    console.error('Usage: pnpm --filter api exec tsx scripts/verify-password.ts <email> "<password>"');
    process.exit(1);
  }

  const user = await prisma.user.findUnique({
    where: { email: email.toLowerCase() },
    select: {
      id: true,
      email: true,
      username: true,
      passwordHash: true,
      status: true,
    },
  });

  if (!user) {
    console.error("User not found.");
    process.exit(1);
  }

  const ok = await argon2.verify(user.passwordHash, password);

  console.log({
    id: user.id,
    email: user.email,
    username: user.username,
    status: user.status,
    passwordMatches: ok,
  });
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
