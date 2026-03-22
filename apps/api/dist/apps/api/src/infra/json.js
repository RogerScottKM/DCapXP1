"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.safeStringify = exports.jsonReplacer = void 0;
const library_1 = require("@prisma/client/runtime/library");
const jsonReplacer = (_k, v) => {
    if (typeof v === "bigint")
        return v.toString();
    if (v instanceof library_1.Decimal)
        return v.toString();
    return v;
};
exports.jsonReplacer = jsonReplacer;
const safeStringify = (obj) => JSON.stringify(obj, exports.jsonReplacer);
exports.safeStringify = safeStringify;
