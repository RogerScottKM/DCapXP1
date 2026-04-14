import crypto from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const prismaMock = vi.hoisted(() => ({
  requestNonce: {
    create: vi.fn(),
    deleteMany: vi.fn(),
  },
  agent: {
    findUnique: vi.fn(),
  },
  mandateUsage: {
    findUnique: vi.fn(),
    upsert: vi.fn(),
  },
}));

vi.mock("../src/infra/prisma", () => ({ prisma: prismaMock }));

import { bumpNotionalUsed, bumpOrdersPlaced, enforceMandate } from "../src/middleware/ibac";
import { canonicalStringify } from "../src/utils/canonicalJson";
import { utcDay } from "../src/utils/quantums";

function buildMessage(ts: string, nonce: string, method: string, originalUrl: string, body: unknown) {
  const path = String(originalUrl).split("?")[0];
  const bodyStable = canonicalStringify(body ?? {});
  const bodyHash = crypto.createHash("sha256").update(bodyStable).digest("hex");
  return `${ts}.${nonce}.${method}.${path}.${bodyHash}`;
}

function buildSignedRequest(options?: {
  ts?: string;
  nonce?: string;
  method?: string;
  originalUrl?: string;
  body?: any;
  signWithPrivateKey?: crypto.KeyObject;
}) {
  const { publicKey, privateKey } = crypto.generateKeyPairSync("ed25519");
  const publicKeyPem = publicKey.export({ type: "spki", format: "pem" }).toString();
  const ts = options?.ts ?? String(Date.now());
  const nonce = options?.nonce ?? "nonce-1";
  const method = options?.method ?? "POST";
  const originalUrl = options?.originalUrl ?? "/api/v1/trade/orders?mode=LIVE";
  const body = options?.body ?? { symbol: "btc-usd", qty: "1" };
  const signingKey = options?.signWithPrivateKey ?? privateKey;
  const message = buildMessage(ts, nonce, method, originalUrl, body);
  const signature = crypto.sign(null, Buffer.from(message, "utf8"), signingKey).toString("base64");

  const headers: Record<string, string> = {
    "x-agent-id": "agent-1",
    "x-agent-ts": ts,
    "x-agent-nonce": nonce,
    "x-agent-sig": signature,
  };

  const req: any = {
    method,
    originalUrl,
    body,
    principal: undefined,
    headers,
    header(name: string) {
      return headers[name.toLowerCase()] ?? headers[name] ?? undefined;
    },
  };

  return { req, publicKeyPem, privateKey };
}

function makeRes() {
  const res: any = { statusCode: 200, payload: undefined };
  res.status = vi.fn((code: number) => {
    res.statusCode = code;
    return res;
  });
  res.json = vi.fn((payload: unknown) => {
    res.payload = payload;
    return res;
  });
  return res;
}

async function invoke(middleware: ReturnType<typeof enforceMandate>, req: any) {
  const res = makeRes();
  let nextCalled = false;
  await middleware(req, res, () => {
    nextCalled = true;
  });
  return { req, res, nextCalled };
}

function validMandate(overrides?: Record<string, unknown>) {
  const now = Date.now();
  return {
    id: "mandate-1",
    action: "TRADE",
    notBefore: new Date(now - 60_000),
    expiresAt: new Date(now + 60_000),
    market: "BTC-USD",
    maxOrdersPerDay: 5,
    ...(overrides ?? {}),
  };
}

function activeAgent(publicKeyPem: string, mandateOverrides?: Record<string, unknown>) {
  return {
    id: "agent-1",
    userId: "user-1",
    status: "ACTIVE",
    user: { id: "user-1" },
    keys: [{ publicKeyPem, revokedAt: null, createdAt: new Date() }],
    mandates: [validMandate(mandateOverrides)],
  };
}

describe("IBAC mandate middleware", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();
    prismaMock.requestNonce.create.mockResolvedValue({});
    prismaMock.requestNonce.deleteMany.mockResolvedValue({ count: 0 });
    prismaMock.agent.findUnique.mockResolvedValue(null);
    prismaMock.mandateUsage.findUnique.mockResolvedValue(null);
    prismaMock.mandateUsage.upsert.mockResolvedValue({});
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it("rejects requests with missing agent authentication headers", async () => {
    const req: any = {
      method: "POST",
      originalUrl: "/api/v1/trade/orders",
      body: {},
      headers: {},
      header: () => undefined,
    };

    const { res, nextCalled } = await invoke(enforceMandate("TRADE"), req);

    expect(nextCalled).toBe(false);
    expect(res.statusCode).toBe(401);
    expect(res.payload).toEqual({ error: "Missing agent auth headers" });
  });

  it("rejects stale timestamps before signature verification", async () => {
    const { req } = buildSignedRequest({ ts: String(Date.now() - 120_000) });

    const { res, nextCalled } = await invoke(enforceMandate("TRADE"), req);

    expect(nextCalled).toBe(false);
    expect(res.statusCode).toBe(401);
    expect(res.payload).toEqual({ error: "Stale timestamp" });
  });

  it("rejects replayed nonces when the nonce insert hits a unique constraint", async () => {
    prismaMock.requestNonce.create.mockRejectedValue({ code: "P2002" });
    const { req } = buildSignedRequest();

    const { res, nextCalled } = await invoke(enforceMandate("TRADE"), req);

    expect(nextCalled).toBe(false);
    expect(res.statusCode).toBe(401);
    expect(res.payload).toEqual({ error: "Replay nonce" });
  });

  it("rejects invalid or revoked agents", async () => {
    const { req } = buildSignedRequest();
    prismaMock.agent.findUnique.mockResolvedValue(null);

    const { res, nextCalled } = await invoke(enforceMandate("TRADE"), req);

    expect(nextCalled).toBe(false);
    expect(res.statusCode).toBe(403);
    expect(res.payload).toEqual({ error: "Agent invalid/revoked" });
    expect(prismaMock.requestNonce.deleteMany).toHaveBeenCalledTimes(1);
  });

  it("rejects agents without an active key or public key", async () => {
    const { req, publicKeyPem } = buildSignedRequest();
    prismaMock.agent.findUnique.mockResolvedValueOnce({
      ...activeAgent(publicKeyPem),
      keys: [],
    });

    const first = await invoke(enforceMandate("TRADE"), req);
    expect(first.nextCalled).toBe(false);
    expect(first.res.statusCode).toBe(403);
    expect(first.res.payload).toEqual({ error: "No active agent key" });

    prismaMock.agent.findUnique.mockResolvedValueOnce({
      ...activeAgent(publicKeyPem),
      keys: [{ publicKeyPem: "", revokedAt: null, createdAt: new Date() }],
    });

    const second = await invoke(enforceMandate("TRADE"), req);
    expect(second.nextCalled).toBe(false);
    expect(second.res.statusCode).toBe(403);
    expect(second.res.payload).toEqual({ error: "Agent key missing public key" });
  });

  it("rejects invalid agent signatures", async () => {
    const wrongKeyPair = crypto.generateKeyPairSync("ed25519");
    const { req, publicKeyPem } = buildSignedRequest({ signWithPrivateKey: wrongKeyPair.privateKey });
    prismaMock.agent.findUnique.mockResolvedValue(activeAgent(publicKeyPem));

    const { res, nextCalled } = await invoke(enforceMandate("TRADE"), req);

    expect(nextCalled).toBe(false);
    expect(res.statusCode).toBe(403);
    expect(res.payload).toEqual({ error: "Invalid agent signature" });
  });

  it("rejects requests without a valid mandate for the required market", async () => {
    const { req, publicKeyPem } = buildSignedRequest({ body: { symbol: "btc-usd", qty: "1" } });
    prismaMock.agent.findUnique.mockResolvedValue(activeAgent(publicKeyPem, { market: "ETH-USD" }));

    const { res, nextCalled } = await invoke(enforceMandate("TRADE"), req);

    expect(nextCalled).toBe(false);
    expect(res.statusCode).toBe(403);
    expect(res.payload).toEqual({ error: "No valid mandate for action/market" });
  });

  it("rejects requests that exceed mandate maxOrdersPerDay", async () => {
    const { req, publicKeyPem } = buildSignedRequest();
    prismaMock.agent.findUnique.mockResolvedValue(activeAgent(publicKeyPem, { maxOrdersPerDay: 2 }));
    prismaMock.mandateUsage.findUnique.mockResolvedValue({ ordersPlaced: 2 });

    const { res, nextCalled } = await invoke(enforceMandate("TRADE"), req);

    expect(nextCalled).toBe(false);
    expect(res.statusCode).toBe(403);
    expect(res.payload).toEqual({ error: "Mandate maxOrdersPerDay exceeded" });
  });

  it("attaches agent principal context on a valid signed request", async () => {
    const { req, publicKeyPem } = buildSignedRequest({
      originalUrl: "/api/v1/trade/orders?ignored=yes",
      body: { symbol: "btc-usd", qty: "1", nested: { a: 2, b: 1 } },
    });
    prismaMock.agent.findUnique.mockResolvedValue(activeAgent(publicKeyPem));
    prismaMock.mandateUsage.findUnique.mockResolvedValue({ ordersPlaced: 1 });

    const { nextCalled } = await invoke(enforceMandate("TRADE"), req);

    expect(nextCalled).toBe(true);
    expect(req.principal).toEqual({
      type: "AGENT",
      userId: "user-1",
      agentId: "agent-1",
      mandateId: "mandate-1",
    });
    expect(prismaMock.requestNonce.deleteMany).toHaveBeenCalledWith({
      where: { createdAt: { lt: expect.any(Date) } },
    });
  });

  it("bumps order counts and notional usage using the UTC day bucket", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-14T12:34:56.000Z"));
    const day = utcDay(new Date("2026-04-14T12:34:56.000Z"));

    await bumpOrdersPlaced("mandate-1");
    expect(prismaMock.mandateUsage.upsert).toHaveBeenNthCalledWith(1, {
      where: { mandateId_day: { mandateId: "mandate-1", day } },
      create: { mandateId: "mandate-1", day, ordersPlaced: 1 },
      update: { ordersPlaced: { increment: 1 } },
    });

    await bumpNotionalUsed("mandate-1", 1234n);
    expect(prismaMock.mandateUsage.upsert).toHaveBeenNthCalledWith(2, {
      where: { mandateId_day: { mandateId: "mandate-1", day } },
      create: { mandateId: "mandate-1", day, notionalUsed: 1234n },
      update: { notionalUsed: { increment: 1234n } },
    });
  });
});
