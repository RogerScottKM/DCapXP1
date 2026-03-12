// Produces deterministic JSON for hashing/signing (key order stable).
export function canonicalStringify(value: any): string {
  if (value === null || value === undefined) return "null";

  const t = typeof value;

  if (t === "number" || t === "boolean") return JSON.stringify(value);
  if (t === "string") return JSON.stringify(value);

  if (Array.isArray(value)) {
    return `[${value.map(canonicalStringify).join(",")}]`;
  }

  if (t === "object") {
    const keys = Object.keys(value).sort();
    const items = keys.map((k) => `${JSON.stringify(k)}:${canonicalStringify(value[k])}`);
    return `{${items.join(",")}}`;
  }

  // fallback
  return JSON.stringify(value);
}
