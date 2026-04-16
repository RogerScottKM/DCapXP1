import { beforeEach, describe, expect, it, vi } from "vitest";

const { store, prismaMock } = vi.hoisted(() => {
  const store = new Map<string, any>();

  const prismaMock = {
    idempotencyKey: {
      findUnique: vi.fn(async ({ where }: any) => {
        const compound = where.ownerType_ownerId_scope_key;
        const key = `${compound.ownerType}:${compound.ownerId}:${compound.scope}:${compound.key}`;
        return store.get(key) ?? null;
      }),
      create: vi.fn(async ({ data }: any) => {
        const key = `${data.ownerType}:${data.ownerId}:${data.scope}:${data.key}`;
        if (store.has(key)) {
          const error: any = new Error("Unique constraint");
          error.code = "P2002";
          throw error;
        }
        const record = { id: `idem-${store.size + 1}`, ...data };
        store.set(key, record);
        return record;
      }),
      update: vi.fn(async ({ where, data }: any) => {
        for (const [k, value] of store.entries()) {
          if (value.id === where.id) {
            const next = { ...value, ...data };
            store.set(k, next);
            return next;
          }
        }
        throw new Error("Record not found");
      }),
      delete: vi.fn(async ({ where }: any) => {
        for (const [k, value] of store.entries()) {
          if (value.id === where.id) {
            store.delete(k);
            return value;
          }
        }
        return null;
      }),
    },
  };

  return { store, prismaMock };
});

vi.mock("../src/lib/prisma", () => ({ prisma: prismaMock }));

import { withIdempotency } from "../src/lib/idempotency";

function makeReq(body: any, key = "idem-1"): any {
  return {
    method: "POST",
    path: "/api/orders",
    params: {},
    query: {},
    body,
    auth: { userId: "user-1" },
    headers: { "idempotency-key": key },
    get(name: string) {
      return this.headers[String(name).toLowerCase()] ?? null;
    },
    header(name: string) {
      return this.get(name);
    },
  };
}

function makeRes(): any {
  const res: any = {};
  res.statusCode = 200;
  res.body = undefined;
  res.status = vi.fn((code: number) => {
    res.statusCode = code;
    return res;
  });
  res.json = vi.fn((body: any) => {
    res.body = body;
    return res;
  });
  return res;
}

describe("idempotency helper", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    store.clear();
  });

  it("replays the stored response for the same key and same payload", async () => {
    const handler = vi.fn(async (_req, res) => {
      return res.status(201).json({ ok: true, orderId: "ord-1" });
    });

    const wrapped = withIdempotency("HUMAN_ORDER_PLACE", handler);

    const req1 = makeReq({ symbol: "BTC-USD", qty: "1", price: "100" }, "same-key");
    const res1 = makeRes();
    await wrapped(req1, res1);

    const req2 = makeReq({ symbol: "BTC-USD", qty: "1", price: "100" }, "same-key");
    const res2 = makeRes();
    await wrapped(req2, res2);

    expect(handler).toHaveBeenCalledTimes(1);
    expect(res1.statusCode).toBe(201);
    expect(res1.body).toEqual({ ok: true, orderId: "ord-1" });
    expect(res2.statusCode).toBe(201);
    expect(res2.body).toEqual({ ok: true, orderId: "ord-1" });
  });

  it("rejects the same key reused with a different payload", async () => {
    const handler = vi.fn(async (_req, res) => {
      return res.status(201).json({ ok: true, orderId: "ord-2" });
    });

    const wrapped = withIdempotency("HUMAN_ORDER_PLACE", handler);

    const req1 = makeReq({ symbol: "BTC-USD", qty: "1", price: "100" }, "same-key");
    const res1 = makeRes();
    await wrapped(req1, res1);

    const req2 = makeReq({ symbol: "BTC-USD", qty: "2", price: "100" }, "same-key");
    const res2 = makeRes();
    await wrapped(req2, res2);

    expect(handler).toHaveBeenCalledTimes(1);
    expect(res2.statusCode).toBe(409);
    expect(res2.body).toEqual(
      expect.objectContaining({
        error: "Idempotency key reuse with different payload.",
      }),
    );
  });

  it("runs normally when no idempotency key is provided", async () => {
    const handler = vi.fn(async (_req, res) => {
      return res.status(201).json({ ok: true });
    });

    const wrapped = withIdempotency("HUMAN_ORDER_PLACE", handler);

    const req = makeReq({ symbol: "BTC-USD" }, "");
    delete req.headers["idempotency-key"];

    await wrapped(req, makeRes());
    await wrapped(req, makeRes());

    expect(handler).toHaveBeenCalledTimes(2);
  });
});
