import { Prisma } from "@prisma/client";
import { RegisterDto } from "./auth.dto";

export function mapRegisterDtoToUserCreate(
  dto: RegisterDto,
  passwordHash: string,
): Prisma.UserCreateInput {
  return {
    email: dto.email,
    username: dto.username,
    phone: dto.phone,
    status: "REGISTERED",
    passwordHash,
    profile: {
      create: {
        firstName: dto.firstName,
        lastName: dto.lastName,
        fullName: `${dto.firstName} ${dto.lastName}`.trim(),
        country: dto.country,
        sourceChannel: dto.sourceChannel,
      },
    },
  };
}
