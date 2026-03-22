"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.prisma = void 0;
/** import { PrismaClient } from "@prisma/client";*/
var prisma_1 = require("./infra/prisma");
Object.defineProperty(exports, "prisma", { enumerable: true, get: function () { return prisma_1.prisma; } });
/**
declare global {
  // eslint-disable-next-line no-var
  var __prisma: PrismaClient | undefined;
}

export const prisma =
  global.__prisma ??
  new PrismaClient({
    log: process.env.NODE_ENV === "production" ? ["error"] : ["warn", "error"],
  });

if (process.env.NODE_ENV !== "production") {
  global.__prisma = prisma;
} */
