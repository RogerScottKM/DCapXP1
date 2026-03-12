import crypto from "crypto";
import fs from "fs";

function sha256hex(s: string) {
  return crypto.createHash("sha256").update(s).digest("hex");
}

function canonicalStringify(value: any): string {
  if (value === null || value === undefined) return "null";
  const t = typeof value;
  if (t === "number" || t === "boolean") return JSON.stringify(value);
  if (t === "string") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalStringify).join(",")}]`;
  if (t === "object") {
    const keys = Object.keys(value).sort();
    const items = keys.map((k) => `${JSON.stringify(k)}:${canonicalStringify(value[k])}`);
    return `{${items.join(",")}}`;
  }
  return JSON.stringify(value);
}

function signEd25519(privateKeyPem: string, message: string): string {
  const sig = crypto.sign(null, Buffer.from(message, "utf8"), privateKeyPem);
  return sig.toString("base64");
}

async function main() {
  const AGENT_ID = process.env.AGENT_ID!;
  const PRIVATE_KEY_PEM =
    process.env.AGENT_PRIVATE_KEY_PEM ??
    fs.readFileSync(process.env.AGENT_PRIVATE_KEY_PATH!, "utf8");

  const API_BASE = process.env.API_BASE ?? "http://localhost:4010";

  const url = `${API_BASE}/v1/agent/orders`;
  const path = "/v1/agent/orders"; // MUST match server signed path

  const body = {
    symbol: "RVAI-USD",
    side: "BUY",
    qty: "100",
    price: "0.10",
  };

  const ts = String(Date.now());
  const nonce = crypto.randomBytes(16).toString("hex");
  const bodyHash = sha256hex(canonicalStringify(body));
  const msg = `${ts}.${nonce}.POST.${path}.${bodyHash}`;
  const sig = signEd25519(PRIVATE_KEY_PEM, msg);

  const r = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-agent-id": AGENT_ID,
      "x-agent-ts": ts,
      "x-agent-nonce": nonce,
      "x-agent-sig": sig,
    },
    body: JSON.stringify(body),
  });

  console.log(await r.json());
}

main().catch(console.error);
