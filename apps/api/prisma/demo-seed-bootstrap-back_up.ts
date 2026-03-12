// apps/api/prisma/seed.ts
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();
const ISSUER_CONTROLLED_ASSETS = new Set(["RVAI", "RVGX", "APTV"]);
const isIssuerControlled = (code: string) => ISSUER_CONTROLLED_ASSETS.has(code);

// small deterministic RNG (stable demo)
function mulberry32(seed: number) {
  return function () {
    let t = (seed += 0x6d2b79f5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function pick<T>(rng: () => number, arr: T[]) {
  return arr[Math.floor(rng() * arr.length)];
}

function randInt(rng: () => number, min: number, max: number) {
  return Math.floor(rng() * (max - min + 1)) + min;
}

function randFloat(rng: () => number, min: number, max: number) {
  return rng() * (max - min) + min;
}

type MarketSeed = {
  symbol: string;
  base: string;
  quote: string;
  tick: string;
  lot: string;
  sourceSymbol?: string;
};

const MARKETS: MarketSeed[] = [
  { symbol: "BTC-USD", base: "BTC", quote: "USD", tick: "0.5", lot: "0.0001", sourceSymbol: "COINBASE:BTCUSD" },
  { symbol: "ETH-USD", base: "ETH", quote: "USD", tick: "0.05", lot: "0.001", sourceSymbol: "COINBASE:ETHUSD" },
  { symbol: "XRP-USD", base: "XRP", quote: "USD", tick: "0.0001", lot: "1", sourceSymbol: "COINBASE:XRPUSD" },
  { symbol: "SOL-USD", base: "SOL", quote: "USD", tick: "0.01", lot: "0.01", sourceSymbol: "COINBASE:SOLUSD" },

  { symbol: "RVAI-USD", base: "RVAI", quote: "USD", tick: "0.0001", lot: "1" },
  { symbol: "RVGX-USD", base: "RVGX", quote: "USD", tick: "0.0001", lot: "1" },
  { symbol: "APTV-USD", base: "APTV", quote: "USD", tick: "0.0001", lot: "1" },

  { symbol: "XAU-USD", base: "XAU", quote: "USD", tick: "0.1", lot: "0.001", sourceSymbol: "OANDA:XAUUSD" },
  { symbol: "XAG-USD", base: "XAG", quote: "USD", tick: "0.001", lot: "0.01", sourceSymbol: "OANDA:XAGUSD" },

  // FX-style (display symbols can be whatever you standardize on)
  { symbol: "USD-EUR", base: "USD", quote: "EUR", tick: "0.0001", lot: "10", sourceSymbol: "OANDA:USDEUR" },
  { symbol: "USD-JPY", base: "USD", quote: "JPY", tick: "0.01", lot: "10", sourceSymbol: "OANDA:USDJPY" },
  { symbol: "USD-AUD", base: "USD", quote: "AUD", tick: "0.0001", lot: "10", sourceSymbol: "OANDA:USDAUD" },
];

function assetKind(code: string) {
  if (["USD", "EUR", "JPY", "AUD"].includes(code)) return "FIAT";
  if (["XAU", "XAG"].includes(code)) return "COMMODITY";
  if (["RVAI", "RVGX", "APTV"].includes(code)) return "TOKEN";
  return "CRYPTO";
}

async function reset() {
  console.log("Resetting…");

  // Delete in FK-safe order: deepest children -> parents
  await prisma.$transaction([
    // ===== Trades/Orders/Balances (if present in your schema) =====
    prisma.trade.deleteMany(),
    prisma.order.deleteMany(),
    prisma.balance.deleteMany(),

    // ===== Digital twin graph =====
    prisma.twinAgentAssignment.deleteMany(),
    prisma.digitalTwinProfile.deleteMany(),

    // ===== KYC =====
    prisma.kyc.deleteMany(),

    // ===== IBAC / Agents graph =====
    prisma.mandateUsage.deleteMany(),
    prisma.mandate.deleteMany(),
    prisma.agentKey.deleteMany(),
    prisma.requestNonce.deleteMany(), // not a FK, but clean it anyway
    prisma.agent.deleteMany(),

    // ===== Finally, users =====
    prisma.user.deleteMany(),
  ]);
}

async function seedCatalog() {
  // Assets
  const assetCodes = Array.from(
    new Set(MARKETS.flatMap((m) => [m.base, m.quote]))
  );

  for (const code of assetCodes) {
    await prisma.asset.upsert({
      where: { code },
      update: { kind: assetKind(code) as any, issuerControlled: isIssuerControlled(code) },
      create: { code, kind: assetKind(code) as any, issuerControlled: isIssuerControlled(code) } 
    });
  }

  // Markets (legacy) + Instruments (future-proof)
  for (const m of MARKETS) {
    await prisma.market.upsert({
      where: { symbol: m.symbol },
      update: {
        baseAsset: m.base,
        quoteAsset: m.quote,
        tickSize: m.tick,
        lotSize: m.lot,
      },
      create: {
        symbol: m.symbol,
        baseAsset: m.base,
        quoteAsset: m.quote,
        tickSize: m.tick,
        lotSize: m.lot,
      },
    });

    const base = await prisma.asset.findUnique({ where: { code: m.base } });
    const quote = await prisma.asset.findUnique({ where: { code: m.quote } });
    if (!base || !quote) throw new Error("Missing asset in catalog");

    await prisma.instrument.upsert({
      where: { displaySymbol: m.symbol },
      update: {
        sourceSymbol: m.sourceSymbol ?? null,
        legacySymbol: m.symbol,
        baseAssetId: base.id,
        quoteAssetId: quote.id,
      },
      create: {
        displaySymbol: m.symbol,
        sourceSymbol: m.sourceSymbol ?? null,
        legacySymbol: m.symbol,
        baseAssetId: base.id,
        quoteAssetId: quote.id,
      },
    });
  }
}

async function seedAgents() {
  // 1) Create/reuse a "house/system" user (required FK for Agent.userId)
  const houseUser = await prisma.user.upsert({
    where: { email: "house@dcapx.local" },
    update: {},
    create: {
      email: "house@dcapx.local",
      username: "house",
      passwordHash: "DEV_SEED_ONLY_DO_NOT_USE_IN_PROD",
      totpSecret: null,
    },
  });

  const agents = [
    { name: "Aegis RiskGuard", kind: "RISK_GUARD", role: "risk" },
    { name: "Atlas MarketMaker", kind: "MARKET_MAKER", role: "primary" },
    { name: "Kite Scalper", kind: "SCALPER", role: "primary" },
    { name: "Orchid MeanRevert", kind: "MEAN_REVERT", role: "primary" },
    { name: "Falcon TrendFollow", kind: "TREND_FOLLOW", role: "primary" },
    { name: "Harbor DCA", kind: "DCA", role: "primary" },
    { name: "Scribe NewsSentiment", kind: "NEWS_SENTIMENT", role: "copilot" },
    { name: "Argo Arbitrage", kind: "ARBITRAGE", role: "copilot" },
    { name: "Crown PortfolioMgr", kind: "PORTFOLIO_MANAGER", role: "copilot" },
  ] as const;

  const created = [];

  for (const a of agents) {
    // 2) Make seeding re-runnable: find existing by (userId + name)
    const existing = await prisma.agent.findFirst({
      where: { userId: houseUser.id, name: a.name },
    });

    if (existing) {
      // optional: keep it updated if schema changes
      const updated = await prisma.agent.update({
        where: { id: existing.id },
        data: {
          kind: a.kind as any,
          version: "1.0",
          status: "ACTIVE",
          config: { notes: "demo agent" },
        },
      });
      created.push(updated);
      continue;
    }

    const agent = await prisma.agent.create({
      data: {
        userId: houseUser.id, // ✅ required
        name: a.name,
        kind: a.kind as any,
        version: "1.0",
        status: "ACTIVE",
        config: { notes: "demo agent" },
      },
    });

    created.push(agent);
  }

  return created;
}

function tierPlan(tier: string, symbols: string[], rng: () => number) {
  const riskPct =
    tier === "WHALE"
      ? randFloat(rng, 0.001, 0.008)
      : tier === "TRADER"
      ? randFloat(rng, 0.005, 0.02)
      : tier === "SCALPER"
      ? randFloat(rng, 0.002, 0.01)
      : tier === "LEARNER"
      ? randFloat(rng, 0.002, 0.008)
      : randFloat(rng, 0.001, 0.006);

  const maxOrders =
    tier === "WHALE"
      ? randInt(rng, 50, 200)
      : tier === "TRADER"
      ? randInt(rng, 80, 250)
      : tier === "SCALPER"
      ? randInt(rng, 150, 600)
      : tier === "LEARNER"
      ? randInt(rng, 20, 80)
      : randInt(rng, 10, 60);

  return {
    riskPct: riskPct.toFixed(4),
    maxOrdersPerDay: maxOrders,
    preferredSymbols: symbols,
    plan: {
      mode: "PAPER",
      tier,
      allowedSymbols: symbols,
      risk: {
        perTradePct: riskPct,
        dailyMaxOrders: maxOrders,
        maxSlippageBps: tier === "SCALPER" ? 5 : 20,
        fatFingerBands: true,
      },
      behavior: {
        style:
          tier === "WHALE"
            ? "patient-liquidity"
            : tier === "SCALPER"
            ? "micro-mean-revert"
            : tier === "TRADER"
            ? "trend + pullback"
            : tier === "LEARNER"
            ? "guided-sim"
            : "ultra-safe",
        timeframes: ["1m", "5m", "1h", "1d"],
      },
      coaching: {
        enabled: true,
        tone: tier === "LEARNER" || tier === "NEWBIE" ? "teaching" : "concise",
      },
    },
  };
}

async function seedTwinsAndBalances(agentRows: { id: string; name: string; kind: string }[]) {
  const rng = mulberry32(42);

  const tiers: { tier: any; count: number }[] = [
    { tier: "WHALE", count: 10 },
    { tier: "TRADER", count: 25 },
    { tier: "SCALPER", count: 15 },
    { tier: "LEARNER", count: 25 },
    { tier: "NEWBIE", count: 25 },
  ];

  const countries = ["VN", "AU", "UAE", "SG", "US", "GB"];
  const first = ["Alex", "Minh", "Dung", "Huy", "Linh", "Thao", "Peter", "An", "Khanh", "Mai"];
  const last = ["Nguyen", "Tran", "Le", "Pham", "Hoang", "Vu", "Do", "Bui", "Dang", "Phan"];

  const allSymbols = MARKETS.map((m) => m.symbol);
  const coreSymbols = ["BTC-USD", "ETH-USD", "XRP-USD", "SOL-USD", "XAU-USD", "RVAI-USD", "RVGX-USD", "APTV-USD"];

  const riskGuard = agentRows.find((a) => a.kind === "RISK_GUARD");
  if (!riskGuard) throw new Error("Missing risk guard agent");

  let idx = 1;

  for (const t of tiers) {
    for (let i = 0; i < t.count; i++) {
      const username = `twin_${String(idx).padStart(3, "0")}_${String(t.tier).toLowerCase()}`;
      idx++;

      const country = pick(rng, countries);
      const legalName = `${pick(rng, first)} ${pick(rng, last)}`;

      const preferred =
        t.tier === "WHALE"
          ? pick(rng, [coreSymbols, allSymbols, ["BTC-USD", "ETH-USD", "XAU-USD", "RVAI-USD"]])
          : t.tier === "SCALPER"
          ? pick(rng, [["BTC-USD", "ETH-USD"], ["BTC-USD", "XRP-USD"], ["ETH-USD", "SOL-USD"]])
          : t.tier === "TRADER"
          ? pick(rng, [["BTC-USD", "ETH-USD", "SOL-USD"], ["BTC-USD", "XAU-USD"], ["ETH-USD", "XRP-USD"]])
          : t.tier === "LEARNER"
          ? pick(rng, [["BTC-USD"], ["ETH-USD"], ["XAU-USD"], ["RVAI-USD"]])
          : pick(rng, [["BTC-USD"], ["ETH-USD"], ["XRP-USD"]]);

      const profile = tierPlan(String(t.tier), preferred, rng);

//      const username = `twin_${String(i + 1).padStart(3, "0")}_${String(t.tier).toLowerCase()}`;
      const email = `${username}@twins.dcapx.local`;

// NOTE: this is seed-only. Replace with a real argon2 hash if you want realism.
const passwordHash = "DEV_SEED_ONLY_DO_NOT_USE_IN_PROD";

const user = await prisma.user.create({
  data: {
    email,
    username,
    passwordHash,
    totpSecret: null, // optional

    kyc: {
      create: {
        legalName: "Linh Dang",
        country: "SG",
        dob: new Date("1993-08-25T00:00:00.000Z"),
        docType: "PASSPORT",
        docHash: `demo:${username}:${Math.floor(rng() * 1e9)}`,
        status: "APPROVED",
        riskScore: String((rng() * 3).toFixed(6)), // Prisma Decimal accepts string
      },
    },
  },
  include: { kyc: true },
});


      await prisma.digitalTwinProfile.create({
        data: {
          userId: user.id,
          tier: t.tier,
          riskPct: profile.riskPct,
          maxOrdersPerDay: profile.maxOrdersPerDay,
          preferredSymbols: profile.preferredSymbols,
          plan: profile.plan,
        },
      });

      // Assign agents
      const primary =
        t.tier === "WHALE"
          ? agentRows.find((a) => a.kind === "PORTFOLIO_MANAGER") ?? agentRows[0]
          : t.tier === "SCALPER"
          ? agentRows.find((a) => a.kind === "SCALPER") ?? agentRows[0]
          : t.tier === "TRADER"
          ? agentRows.find((a) => a.kind === "TREND_FOLLOW") ?? agentRows[0]
          : t.tier === "LEARNER"
          ? agentRows.find((a) => a.kind === "MEAN_REVERT") ?? agentRows[0]
          : agentRows.find((a) => a.kind === "DCA") ?? agentRows[0];

      const copilot = agentRows.find((a) => a.kind === "NEWS_SENTIMENT");

      await prisma.twinAgentAssignment.createMany({
        data: [
          { userId: user.id, agentId: riskGuard.id, role: "risk" },
          { userId: user.id, agentId: primary.id, role: "primary" },
          ...(copilot ? [{ userId: user.id, agentId: copilot.id, role: "copilot" }] : []),
        ],
        skipDuplicates: true,
      });

      // Seed balances (spot-style demo)
      const usd =
        t.tier === "WHALE"
          ? randFloat(rng, 250_000, 5_000_000)
          : t.tier === "TRADER"
          ? randFloat(rng, 25_000, 250_000)
          : t.tier === "SCALPER"
          ? randFloat(rng, 10_000, 80_000)
          : t.tier === "LEARNER"
          ? randFloat(rng, 2_000, 15_000)
          : randFloat(rng, 500, 5_000);

      const btc = t.tier === "WHALE" ? randFloat(rng, 5, 60) : randFloat(rng, 0, 2);
      const eth = t.tier === "WHALE" ? randFloat(rng, 50, 800) : randFloat(rng, 0, 30);

      const balanceRows = [
        { userId: user.id, asset: "USD", amount: usd.toFixed(6) },
        { userId: user.id, asset: "BTC", amount: btc.toFixed(6) },
        { userId: user.id, asset: "ETH", amount: eth.toFixed(6) },
      ];

      // a bit of “our tokens” for everyone
      balanceRows.push({ userId: user.id, asset: "RVAI", amount: randFloat(rng, 0, 50_000).toFixed(6) });
      balanceRows.push({ userId: user.id, asset: "RVGX", amount: randFloat(rng, 0, 20_000).toFixed(6) });

      const balanceRowsWithMode = balanceRows.map((r) => ({
         ...r,
         mode: "PAPER" as any, // or TradeMode.PAPER (see Option B)
      }));
      
      await prisma.balance.createMany({ data: balanceRowsWithMode, skipDuplicates: true });
    }
  }
}

async function seedInitialMarketState() {
  const rng = mulberry32(99);
  const users = await prisma.user.findMany({ select: { id: true } });
  if (users.length < 4) throw new Error("Need users to seed market state");

  // small demo mids (you can replace later with real feeds)
  const mids: Record<string, number> = {
    "BTC-USD": 100.5,
    "ETH-USD": 50.25,
    "XRP-USD": 0.62,
    "SOL-USD": 20.15,
    "RVAI-USD": 1.05,
    "RVGX-USD": 0.55,
    "APTV-USD": 0.25,
    "XAU-USD": 2035.0,
    "XAG-USD": 24.8,
    "USD-EUR": 0.92,
    "USD-JPY": 148.3,
    "USD-AUD": 1.52,
  };

  for (const m of MARKETS) {
    const mid = mids[m.symbol] ?? randFloat(rng, 10, 200);
    const tick = Number(m.tick);

    const u1 = pick(rng, users).id;
    const u2 = pick(rng, users).id;

    // OPEN book levels
    await prisma.order.create({
      data: {
        mode: "PAPER" as any,
        symbol: m.symbol,
        side: "BUY",
        price: (mid - tick).toFixed(8),
        qty: randFloat(rng, 0.5, 5).toFixed(8),
        status: "OPEN",
        userId: u1,
      },
    });

    await prisma.order.create({
      data: {
        mode: "PAPER" as any,
        symbol: m.symbol,
        side: "SELL",
        price: (mid + tick).toFixed(8),
        qty: randFloat(rng, 0.5, 5).toFixed(8),
        status: "OPEN",
        userId: u2,
      },
    });

    // Create a couple FILLED trades (for tape)
    const buy = await prisma.order.create({
      data: {
        mode: "PAPER" as any,
        symbol: m.symbol,
        side: "BUY",
        price: (mid + tick).toFixed(8),
        qty: randFloat(rng, 0.05, 0.5).toFixed(8),
        status: "FILLED",
        userId: u1,
      },
    });

    const sell = await prisma.order.create({
      data: {
        mode: "PAPER" as any,
        symbol: m.symbol,
        side: "SELL",
        price: (mid + tick).toFixed(8),
        qty: buy.qty,
        status: "FILLED",
        userId: u2,
      },
    });

    await prisma.trade.create({
      data: {
        mode: "PAPER" as any,
        symbol: m.symbol,
        price: (mid + tick).toFixed(8),
        qty: String(buy.qty),
        buyOrderId: buy.id,
        sellOrderId: sell.id,
      },
    });
  }
}

async function main() {
  console.log("Resetting…");
  await reset();

  console.log("Seeding catalog…");
  await seedCatalog();

  console.log("Seeding agents…");
  const agents = await seedAgents();

  console.log("Seeding 100 digital twins…");
  await seedTwinsAndBalances(
    agents.map((a) => ({ id: a.id, name: a.name, kind: a.kind as any }))
  );

  console.log("Seeding initial market state…");
  await seedInitialMarketState();

  console.log("Done ✅");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
