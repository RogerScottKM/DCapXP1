"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.inferPersona = inferPersona;
function inferPersona(userId) {
    // v0 deterministic stub — replace with DB/KYC later
    if (userId === 1)
        return "Newbie";
    if (userId === 2)
        return "Scalper";
    if (userId === 3)
        return "Passive";
    return "Whale";
}
