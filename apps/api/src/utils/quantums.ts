export function parseDecimalToBigInt(amount: string, decimals: number): bigint {
  // Accept: "123", "123.4", "123.4500"
  const s = amount.trim();
  if (!/^\d+(\.\d+)?$/.test(s)) throw new Error(`Invalid decimal: ${amount}`);

  const [whole, frac = ""] = s.split(".");
  const fracPadded = (frac + "0".repeat(decimals)).slice(0, decimals);

  const combined = whole + fracPadded;
  return BigInt(combined);
}

export function utcDay(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}
