"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.mapRegisterDtoToUserCreate = mapRegisterDtoToUserCreate;
function mapRegisterDtoToUserCreate(dto, passwordHash) {
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
