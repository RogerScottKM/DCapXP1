// apps/api/src/botFarm.ts
import {
  PrismaClient,
  TradeMode,
  OrderStatus,
  OrderSide,
} from "@prisma/client";

const prisma = new PrismaClient();

type Regime = "calm" | "active" | "panic";

type BandCfg = {
  min: number;
  max: number;

  // Optional tick override if DB tickSize is too coarse
  tickOverride?: number;

  // Baseline per-loop volatility (as % of price)
  driftPct: number;

  // How far prints can wander from mid (in ticks)
  wickTicks: number;

  // Mean reversion toward anchor (0..1)
  pullToAnchor: number;

  // Anchor random-walk strength (as % of band per loop)
  anchorNoisePct: number;

  // Rare jump/shock configuration
  jumpProb: number;
  jumpTicksMin: number;
  jumpTicksMax: number;

  // Regime block length
  regimeMinSec: number;
  regimeMaxSec: number;

  // Ensure tape never feels dead
  forceTradeEveryMs: number;

  // Depth / trimming
  openLevels: number;
  openLimit: number;
  tradeLimit: number;
  staleOpenMs: number;
};

type SymbolState = {
  mid: number;
  anchor: number;
  volPct: number;
  momentum: number;
  regime: Regime;
  regimeUntilMs: number;
  lastTradeAt: number;
  lastCleanupAt: number;
};

type OracleQuote = {
  mid: number;
  bid: number;
  ask: number;
  ts: number;
};

const BANDS: Record<string, BandCfg> = {
  "RVAI-USD": {
    min: Number(process.env.RVAI_MIN ?? 0.083),
    max: Number(process.env.RVAI_MAX ?? 0.12),

    tickOverride: Number(process.env.RVAI_TICK ?? 0.0001),

    // More exciting within the full band
    driftPct: 0.0034,
    wickTicks: 42,

    pullToAnchor: 0.03,
    anchorNoisePct: 0.0105,

    jumpProb: 0.035,
    jumpTicksMin: 60,
    jumpTicksMax: 260,

    regimeMinSec: 18,
    regimeMaxSec: 80,

    forceTradeEveryMs: 1600,

    openLevels: 4,
    openLimit: 160,
    tradeLimit: 9000,
    staleOpenMs: 90_000,
  },

  "BTC-USD": {
    // broad safety rails; live fair value comes from Coinbase oracle
    min: Number(process.env.BTC_MIN ?? 50000),
    max: Number(process.env.BTC_MAX ?? 90000),

    driftPct: 0.00045,
    wickTicks: 12,

    pullToAnchor: 0.02,
    anchorNoisePct: 0.0018,

    jumpProb: 0.015,
    jumpTicksMin: 35,
    jumpTicksMax: 220,

    regimeMinSec: 22,
    regimeMaxSec: 120,

    forceTradeEveryMs: 2200,

    openLevels: 3,
    openLimit: 220,
    tradeLimit: 12000,
    staleOpenMs: 120_000,
  },
};

const ORACLE_PRODUCTS: Record<string, string> = {
  "BTC-USD": "BTC-USD",
};

const oracle: Partial<Record<string, OracleQuote>> = {};

let cachedUserIds: string[] = [];
let cachedUsersAt = 0;

function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

function clamp(n: number, lo: number, hi: number) {
  return Math.max(lo, Math.min(hi, n));
}

function randInt(lo: number, hi: number) {
  return Math.floor(lo + Math.random() * (hi - lo + 1));
}

// Box–Muller gaussian
function randn() {
  let u = 0;
  let v = 0;
  while (u === 0) u = Math.random();
  while (v === 0) v = Math.random();
  return Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
}

function pickRegime(): Regime {
  const r = Math.random();
  if (r < 0.70) return "calm";
  if (r < 0.94) return "active";
  return "panic";
}

function regimeVolMult(regime: Regime) {
  if (regime === "calm") return 1.0;
  if (regime === "active") return 2.5;
  return 4.8;
}

function tradeProb(regime: Regime) {
  if (regime === "calm") return 0.52;
  if (regime === "active") return 0.74;
  return 0.90;
}

function loopSleepMs(regime: Regime) {
  if (regime === "calm") return 380 + Math.random() * 520;
  if (regime === "active") return 140 + Math.random() * 260;
  return 60 + Math.random() * 150;
}

function qtyFor(symbol: string) {
  if (symbol.startsWith("BTC")) {
    return (Math.random() * 0.03 + 0.004).toFixed(8);
  }
  return (Math.random() * 0.18 + 0.015).toFixed(8);
}

function pickTwoDistinct(ids: string[]) {
  const a = ids[Math.floor(Math.random() * ids.length)];
  let b = ids[Math.floor(Math.random() * ids.length)];

  if (ids.length > 1 && a === b) {
    const idx = ids.findIndex((x) => x === a);
    b = ids[(idx + 1) % ids.length];
  }

  return [a, b] as const;
}

async function getActiveUserIds() {
  const now = Date.now();

  if (cachedUserIds.length >= 2 && now - cachedUsersAt < 10_000) {
    return cachedUserIds;
  }

  const rows = await prisma.user.findMany({
    select: { id: true },
    orderBy: { createdAt: "asc" },
  });

  cachedUserIds = rows.map((r) => r.id);
  cachedUsersAt = now;
  return cachedUserIds;
}

async function fetchCoinbaseMid(productId: string): Promise<OracleQuote> {
  const r = await fetch(
    `https://api.exchange.coinbase.com/products/${encodeURIComponent(productId)}/ticker`,
    {
      headers: {
        "user-agent": "dcapx-house-oracle",
        accept: "application/json",
      },
    }
  );

  if (!r.ok) {
    throw new Error(`coinbase ticker ${productId} -> ${r.status}`);
  }

  const j: any = await r.json();
  const bid = Number(j?.bid ?? 0);
  const ask = Number(j?.ask ?? 0);
  const price = Number(j?.price ?? 0);

  const mid =
    Number.isFinite(bid) && Number.isFinite(ask) && bid > 0 && ask > 0
      ? (bid + ask) / 2
      : price;

  if (!Number.isFinite(mid) || mid <= 0) {
    throw new Error(`bad ticker payload for ${productId}`);
  }

  return {
    mid,
    bid: Number.isFinite(bid) && bid > 0 ? bid : mid,
    ask: Number.isFinite(ask) && ask > 0 ? ask : mid,
    ts: Date.now(),
  };
}

async function primeOracles() {
  for (const [symbol, productId] of Object.entries(ORACLE_PRODUCTS)) {
    try {
      oracle[symbol] = await fetchCoinbaseMid(productId);
      console.log(`[botFarm] ${symbol} oracle primed`, oracle[symbol]);
    } catch (e) {
      console.error(`[botFarm] ${symbol} oracle prime failed`, e);
    }
  }
}

async function startOracleWatcher(symbol: string, productId: string) {
  console.log(`[botFarm] house oracle watcher starting for ${symbol}...`);

  while (true) {
    try {
      oracle[symbol] = await fetchCoinbaseMid(productId);
    } catch (e) {
      console.error(`[botFarm] house oracle watcher ${symbol}`, e);
    }

    await sleep(2500);
  }
}

async function scrubPaperOutliers(symbol: string, cfg: BandCfg) {
  let lo = cfg.min;
  let hi = cfg.max;

  // For oracle-backed symbols, scrub fake legacy seed prices aggressively
  if (symbol in ORACLE_PRODUCTS) {
    const live = oracle[symbol];
    if (live && Date.now() - live.ts < 20_000) {
      lo = Math.max(cfg.min, live.mid * 0.50);
      hi = Math.min(cfg.max, live.mid * 1.50);
    } else {
      lo = Math.max(cfg.min, 10_000);
      hi = Math.min(cfg.max, 200_000);
    }
  }

  const loStr = lo.toFixed(8);
  const hiStr = hi.toFixed(8);

  // Delete stale out-of-band trades first
  await prisma.trade.deleteMany({
    where: {
      symbol,
      mode: TradeMode.PAPER,
      OR: [{ price: { lt: loStr } }, { price: { gt: hiStr } }],
    },
  });

  // Delete stale out-of-band OPEN orders
  await prisma.order.deleteMany({
    where: {
      symbol,
      mode: TradeMode.PAPER,
      status: OrderStatus.OPEN,
      OR: [{ price: { lt: loStr } }, { price: { gt: hiStr } }],
    },
  });

  // Delete very old open orders too
  await prisma.order.deleteMany({
    where: {
      symbol,
      mode: TradeMode.PAPER,
      status: OrderStatus.OPEN,
      createdAt: { lt: new Date(Date.now() - 15 * 60 * 1000) },
    },
  });

  // Clean orphan FILLED orders
  await prisma.order.deleteMany({
    where: {
      symbol,
      mode: TradeMode.PAPER,
      status: OrderStatus.FILLED,
      buys: { none: {} },
      sells: { none: {} },
    },
  });
}

async function initState(symbol: string, cfg: BandCfg) {
  const last = await prisma.trade.findFirst({
    where: { symbol, mode: TradeMode.PAPER },
    orderBy: { createdAt: "desc" },
    select: { price: true },
  });

  const live = oracle[symbol];
  const liveFresh = !!live && Date.now() - live.ts < 20_000;

  const fallback = liveFresh ? live!.mid : (cfg.min + cfg.max) / 2;
  const seeded = last ? Number(last.price) : fallback;
  const mid0 = clamp(seeded, cfg.min, cfg.max);

  const regime = pickRegime();
  const durSec = randInt(cfg.regimeMinSec, cfg.regimeMaxSec);
  const now = Date.now();

  return {
    mid: mid0,
    anchor: mid0,
    volPct: cfg.driftPct,
    momentum: 0,
    regime,
    regimeUntilMs: now + durSec * 1000,
    lastTradeAt: 0,
    lastCleanupAt: 0,
  } satisfies SymbolState;
}

async function cleanupSymbolBook(
  symbol: string,
  cfg: BandCfg,
  mid: number,
  nowMs: number
) {
  const midStr = mid.toFixed(8);

  // Delete crossed-looking stale OPEN orders
  await prisma.order.deleteMany({
    where: {
      symbol,
      mode: TradeMode.PAPER,
      status: OrderStatus.OPEN,
      OR: [
        { side: OrderSide.BUY, price: { gt: midStr } },
        { side: OrderSide.SELL, price: { lt: midStr } },
      ],
    },
  });

  // Delete old OPEN orders
  await prisma.order.deleteMany({
    where: {
      symbol,
      mode: TradeMode.PAPER,
      status: OrderStatus.OPEN,
      createdAt: { lt: new Date(nowMs - cfg.staleOpenMs) },
    },
  });

  const openCount = await prisma.order.count({
    where: {
      symbol,
      mode: TradeMode.PAPER,
      status: OrderStatus.OPEN,
    },
  });

  if (openCount > cfg.openLimit) {
    const olds = await prisma.order.findMany({
      where: {
        symbol,
        mode: TradeMode.PAPER,
        status: OrderStatus.OPEN,
      },
      orderBy: { createdAt: "asc" },
      take: openCount - cfg.openLimit,
      select: { id: true },
    });

    if (olds.length) {
      await prisma.order.deleteMany({
        where: { id: { in: olds.map((o) => o.id) } },
      });
    }
  }

  const tradeCount = await prisma.trade.count({
    where: {
      symbol,
      mode: TradeMode.PAPER,
    },
  });

  if (tradeCount > cfg.tradeLimit) {
    const olds = await prisma.trade.findMany({
      where: {
        symbol,
        mode: TradeMode.PAPER,
      },
      orderBy: { createdAt: "asc" },
      take: tradeCount - cfg.tradeLimit,
      select: {
        id: true,
        buyOrderId: true,
        sellOrderId: true,
      },
    });

    if (olds.length) {
      await prisma.trade.deleteMany({
        where: { id: { in: olds.map((t) => t.id) } },
      });

      const orderIds = Array.from(
        new Set(
          olds.flatMap((t) => [t.buyOrderId, t.sellOrderId]).map((x) => x.toString())
        )
      ).map((x) => BigInt(x));

      await prisma.order.deleteMany({
        where: {
          id: { in: orderIds },
          symbol,
          mode: TradeMode.PAPER,
          status: OrderStatus.FILLED,
          buys: { none: {} },
          sells: { none: {} },
        },
      });
    }
  }

  // extra orphan cleanup
  await prisma.order.deleteMany({
    where: {
      symbol,
      mode: TradeMode.PAPER,
      status: OrderStatus.FILLED,
      buys: { none: {} },
      sells: { none: {} },
    },
  });
}

async function placeOpenDepth(
  symbol: string,
  cfg: BandCfg,
  mid: number,
  lo: number,
  hi: number,
  tick: number,
  userIds: string[],
  regime: Regime
) {
  if (userIds.length < 2) return;

  const [maker1, maker2] = pickTwoDistinct(userIds);

  const levels =
    regime === "panic"
      ? cfg.openLevels + 1
      : regime === "active"
      ? cfg.openLevels
      : Math.max(2, cfg.openLevels - 1);

  const openOrders: any[] = [];

  for (let i = 1; i <= levels; i++) {
    const skew = (Math.random() * 0.8 + 0.2) * tick;
    const bid = clamp(mid - tick * i - skew, lo, hi);
    const ask = clamp(mid + tick * i + skew, lo, hi);

    openOrders.push({
      mode: TradeMode.PAPER,
      symbol,
      side: OrderSide.BUY,
      price: bid.toFixed(8),
      qty: qtyFor(symbol),
      status: OrderStatus.OPEN,
      userId: maker1,
    });

    openOrders.push({
      mode: TradeMode.PAPER,
      symbol,
      side: OrderSide.SELL,
      price: ask.toFixed(8),
      qty: qtyFor(symbol),
      status: OrderStatus.OPEN,
      userId: maker2,
    });
  }

  if (openOrders.length) {
    await prisma.order.createMany({ data: openOrders });
  }
}

async function emitPaperTrade(
  symbol: string,
  cfg: BandCfg,
  mid: number,
  lo: number,
  hi: number,
  tick: number,
  userIds: string[],
  regime: Regime
) {
  if (userIds.length < 2) return null;

  const [buyer, seller] = pickTwoDistinct(userIds);
  const qty = qtyFor(symbol);

  const live = oracle[symbol];
  const liveFresh = !!live && Date.now() - live.ts < 10_000;

  const wick =
    cfg.wickTicks *
    (regime === "calm" ? 0.55 : regime === "active" ? 1.0 : 1.45);

  let pxNum =
    symbol in ORACLE_PRODUCTS && liveFresh
      ? live!.mid + randn() * tick * wick
      : mid + randn() * tick * wick;

  const wickOutP =
    regime === "panic" ? 0.18 : regime === "active" ? 0.10 : 0.06;

  if (Math.random() < wickOutP) {
    pxNum += randn() * tick * wick * 2.2;
  }

  pxNum = clamp(pxNum, lo, hi);
  const px = pxNum.toFixed(8);

  const [buy, sell] = await prisma.$transaction([
    prisma.order.create({
      data: {
        mode: TradeMode.PAPER,
        symbol,
        side: OrderSide.BUY,
        price: px,
        qty,
        status: OrderStatus.FILLED,
        userId: buyer,
      },
      select: { id: true },
    }),
    prisma.order.create({
      data: {
        mode: TradeMode.PAPER,
        symbol,
        side: OrderSide.SELL,
        price: px,
        qty,
        status: OrderStatus.FILLED,
        userId: seller,
      },
      select: { id: true },
    }),
  ]);

  await prisma.trade.create({
    data: {
      mode: TradeMode.PAPER,
      symbol,
      price: px,
      qty,
      buyOrderId: buy.id,
      sellOrderId: sell.id,
    },
  });

  return pxNum;
}

async function startSymbolWorker(symbol: string, tickDb: number) {
  const cfg = BANDS[symbol];
  if (!cfg) return;

  await scrubPaperOutliers(symbol, cfg);

  const s = await initState(symbol, cfg);

  console.log(`[botFarm] paper synthesizer starting for ${symbol}...`);

  while (true) {
    try {
      const tNow = Date.now();
      const userIds = await getActiveUserIds();

      if (userIds.length < 2) {
        await sleep(1000);
        continue;
      }

      const tick = cfg.tickOverride ?? tickDb ?? 0.01;
      let lo = cfg.min;
      let hi = cfg.max;

      const live = oracle[symbol];
      const liveFresh = !!live && tNow - live.ts < 10_000;

      // Oracle-backed symbols center tightly around live price
      if (symbol in ORACLE_PRODUCTS && liveFresh) {
        s.anchor = s.anchor * 0.78 + live!.mid * 0.22;
        s.mid = s.mid * 0.90 + live!.mid * 0.10;

        lo = Math.max(cfg.min, live!.mid * 0.965);
        hi = Math.min(cfg.max, live!.mid * 1.035);
      }

      const range = Math.max(hi - lo, tick * 100);

      // Regime rolls
      if (tNow > s.regimeUntilMs) {
        s.regime = pickRegime();
        s.regimeUntilMs =
          tNow + randInt(cfg.regimeMinSec, cfg.regimeMaxSec) * 1000;
      }

      const volMult = regimeVolMult(s.regime);

      // Anchor random walk
      let anchorStep =
        randn() * range * cfg.anchorNoisePct * (0.10 * volMult);

      // RVAI-specific sweep bias so it explores the whole band more often
      if (symbol === "RVAI-USD") {
        const bandPos = (s.anchor - lo) / range; // 0..1
        const sweepBias = (0.5 - bandPos) * range * 0.035;
        anchorStep += sweepBias;
      }

      s.anchor = clamp(s.anchor + anchorStep, lo, hi);

      // Volatility clustering
      {
        const baseline = cfg.driftPct;
        const target = baseline * (0.55 + 0.65 * volMult);

        s.volPct = clamp(
          s.volPct * 0.84 + target * 0.16,
          baseline * 0.25,
          baseline * 10
        );

        s.volPct *= 1 + Math.abs(randn()) * 0.03;
      }

      // Momentum
      const momCap = tick * cfg.wickTicks * 1.25;
      s.momentum = clamp(
        s.momentum * 0.86 +
          randn() * tick * cfg.wickTicks * 0.04 * volMult,
        -momCap,
        momCap
      );

      // Mid update
      let mid = s.mid;
      mid = mid * (1 + randn() * s.volPct);
      mid = mid + (s.anchor - mid) * cfg.pullToAnchor;
      mid = mid + s.momentum;

      // Rare jump shocks
      {
        const jumpP = cfg.jumpProb * (s.regime === "panic" ? 1.7 : 1.0);

        if (Math.random() < jumpP) {
          const sign = Math.random() < 0.5 ? -1 : 1;
          const jumpTicks =
            randInt(cfg.jumpTicksMin, cfg.jumpTicksMax) *
            (s.regime === "panic" ? 2 : 1);

          mid = mid + sign * tick * jumpTicks;
          s.anchor = clamp(s.anchor + sign * range * 0.06, lo, hi);
        }
      }

      // Keep oracle-backed synth reasonably close to live
      if (symbol in ORACLE_PRODUCTS && liveFresh) {
        mid = mid * 0.88 + live!.mid * 0.12;
      }

      mid = clamp(mid, lo, hi);
      s.mid = mid;

      // Periodic cleanup
      if (tNow - s.lastCleanupAt > 12_000) {
        await cleanupSymbolBook(symbol, cfg, mid, tNow);
        s.lastCleanupAt = tNow;
      }

      // Build fresh open depth
      await placeOpenDepth(symbol, cfg, mid, lo, hi, tick, userIds, s.regime);

      // Keep tape alive
      const mustTrade = tNow - s.lastTradeAt > cfg.forceTradeEveryMs;
      const shouldTrade = mustTrade || Math.random() < tradeProb(s.regime);

      if (shouldTrade) {
        const pxNum = await emitPaperTrade(
          symbol,
          cfg,
          mid,
          lo,
          hi,
          tick,
          userIds,
          s.regime
        );

        if (typeof pxNum === "number") {
          s.mid = clamp(s.mid * 0.75 + pxNum * 0.25, lo, hi);
          s.lastTradeAt = Date.now();
        }
      }
    } catch (e: any) {
      console.error(`[botFarm] paper synthesizer ${symbol}`, e);
      // force refresh of user cache on next loop
      cachedUsersAt = 0;
      await sleep(1500);
    }

    await sleep(loopSleepMs(s.regime));
  }
}

export async function startBotFarm() {
  console.log("[botFarm] starting...");

  await primeOracles();

  // Start dedicated house oracle watchers
  for (const [symbol, productId] of Object.entries(ORACLE_PRODUCTS)) {
    void startOracleWatcher(symbol, productId);
  }

  const supportedSymbols = Object.keys(BANDS);

  const markets = await prisma.market.findMany({
    where: {
      symbol: {
        in: supportedSymbols,
      },
    },
    select: {
      symbol: true,
      tickSize: true,
    },
  });

  if (!markets.length) {
    console.log("[botFarm] no supported markets found");
    return;
  }

  const users = await getActiveUserIds();
  if (users.length < 2) {
    console.log("[botFarm] needs at least 2 users");
    return;
  }

  for (const m of markets) {
    const tickDb = Number(m.tickSize || 0.01);
    void startSymbolWorker(m.symbol, tickDb);
  }
}
