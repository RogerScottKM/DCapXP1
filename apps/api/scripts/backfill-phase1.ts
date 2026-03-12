import { PrismaClient, KycCaseStatus, UserStatus, AptivioProfileStatus } from "@prisma/client";

const prisma = new PrismaClient();

async function backfillUsers() {
  const users = await prisma.user.findMany({
    select: {
      id: true,
      email: true,
      username: true,
      createdAt: true,
      kyc: true,
      digitalTwinProfile: true,
      aptivioProfile: true,
    },
  });

  for (const user of users) {
    await prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: user.id },
        data: {
          status: UserStatus.ACTIVE,
          emailVerifiedAt: user.createdAt,
        },
      });

      await tx.userProfile.upsert({
        where: { userId: user.id },
        update: {},
        create: {
          userId: user.id,
          firstName: user.username,
          lastName: "",
          fullName: user.username,
          sourceChannel: "legacy_exchange",
        },
      });

      if (user.kyc) {
        await tx.kycCase.upsert({
          where: { id: `legacy_${user.kyc.id}` },
          update: {},
          create: {
            id: `legacy_${user.kyc.id}`,
            userId: user.id,
            status:
              user.kyc.status === "APPROVED"
                ? KycCaseStatus.APPROVED
                : user.kyc.status === "REJECTED"
                ? KycCaseStatus.REJECTED
                : KycCaseStatus.SUBMITTED,
            notes: "Backfilled from legacy Kyc table",
            startedAt: user.kyc.createdAt,
            submittedAt: user.kyc.createdAt,
            reviewedAt:
              user.kyc.status === "PENDING" ? null : user.kyc.updatedAt,
          },
        });
      }

      await tx.aptivioProfile.upsert({
        where: { userId: user.id },
        update: {},
        create: {
          userId: user.id,
          status: AptivioProfileStatus.DRAFT,
          version: "v1.0.0",
          twinJson: user.digitalTwinProfile
            ? {
                tier: user.digitalTwinProfile.tier,
                riskPct: user.digitalTwinProfile.riskPct.toString(),
                maxOrdersPerDay: user.digitalTwinProfile.maxOrdersPerDay,
                preferredSymbols: user.digitalTwinProfile.preferredSymbols,
                plan: user.digitalTwinProfile.plan,
              }
            : undefined,
        },
      });
    });
  }
}

async function main() {
  await backfillUsers();
  console.log("Phase 1 backfill complete");
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
