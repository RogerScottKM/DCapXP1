"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.prisma = void 0;
const client_1 = require("@prisma/client");
exports.prisma = globalThis.__dcapx_prisma ??
    new client_1.PrismaClient({
    // log: ["error", "warn"], // optional
    });
if (process.env.NODE_ENV !== "production") {
    globalThis.__dcapx_prisma = exports.prisma;
}
