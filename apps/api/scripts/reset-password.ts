import argon2 from "argon2";
import { prisma } from "../src/lib/prisma";

async function main() {
  const email = process.argv[2];
  const newPassword = process.argv[3];

  if (!email || !newPassword) {
    console.error('Usage: pnpm --filter api exec tsx scripts/reset-password.ts <email> "<newPassword>"');
    process.exit(1);
  }

  const user = await prisma.user.findUnique({
    where: { email: email.toLowerCase() },
    select: { id: true, email: true, username: true },
  });

  if (!user) {
    console.error("User not found.");
    process.exit(1);
  }

  const passwordHash = await argon2.hash(newPassword);

  await prisma.user.update({
    where: { id: user.id },
    data: { passwordHash },
  });

  console.log({
    ok: true,
    email: user.email,
    username: user.username,
    message: "Password reset successfully.",
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
