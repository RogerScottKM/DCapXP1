import argon2 from "argon2";
import { prisma } from "../../lib/prisma";
import { withTx } from "../../lib/service/tx";
import { writeAuditEvent } from "../../lib/service/audit";
import { parseDto } from "../../lib/service/zod";
import { registerDto, RegisterDto } from "./auth.dto";
import { mapRegisterDtoToUserCreate } from "./auth.mappers";

export async function registerUser(input: unknown) {
  const dto = parseDto(registerDto, input);

  const passwordHash = await argon2.hash("temporary-password-to-be-reset");

  return withTx(prisma, async (tx) => {
    const user = await tx.user.create({
      data: mapRegisterDtoToUserCreate(dto, passwordHash),
      include: { profile: true },
    });

    await writeAuditEvent(tx, {
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
