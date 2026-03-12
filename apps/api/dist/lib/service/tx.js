"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.withTx = withTx;
async function withTx(prisma, fn) {
    return prisma.$transaction((tx) => fn(tx));
}
