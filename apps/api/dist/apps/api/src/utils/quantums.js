"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseDecimalToBigInt = parseDecimalToBigInt;
exports.utcDay = utcDay;
function parseDecimalToBigInt(amount, decimals) {
    // Accept: "123", "123.4", "123.4500"
    const s = amount.trim();
    if (!/^\d+(\.\d+)?$/.test(s))
        throw new Error(`Invalid decimal: ${amount}`);
    const [whole, frac = ""] = s.split(".");
    const fracPadded = (frac + "0".repeat(decimals)).slice(0, decimals);
    const combined = whole + fracPadded;
    return BigInt(combined);
}
function utcDay(d) {
    return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}
