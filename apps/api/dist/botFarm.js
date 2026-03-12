"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.startBotFarm = startBotFarm;
// apps/api/src/botFarm.ts
const client_1 = require("@prisma/client");
const prisma = new client_1.PrismaClient();
const BANDS = {
    "RVAI-USD": {
        min: Number(process.env.RVAI_MIN ?? 0.083),
        max: Number(process.env.RVAI_MAX ?? 0.12),
        // If your Market.tickSize for RVAI is still 0.01, override it here:
        tickOverride: Number(process.env.RVAI_TICK ?? 0.0001),
        // RVAI: lively but contained
        driftPct: 0.0018, // ~0.18% gaussian noise per loop baseline
        wickTicks: 22, // increase this to see more wicks
        pullToAnchor: 0.07, // mild mean reversion
        anchorNoisePct: 0.0032, // anchor wanders => no sine
        jumpProb: 0.018, // rare “shock”
        jumpTicksMin: 30,
        jumpTicksMax: 220,
        regimeMinSec: 20,
        regimeMaxSec: 120,
    },
    "BTC-USD": {
        // broad fallback band only; live anchor comes from Coinbase watcher
        min: Number(process.env.BTC_MIN ?? 50000),
        max: Number(process.env.BTC_MAX ?? 90000),
        driftPct: 0.00035,
        wickTicks: 10,
        pullToAnchor: 0.03,
        anchorNoisePct: 0.0014,
        jumpProb: 0.012,
        jumpTicksMin: 40,
        jumpTicksMax: 300,
        regimeMinSec: 25,
        regimeMaxSec: 140,
    },
};
const oracle = {};
function sleep(ms) {
    return new Promise((r) => setTimeout(r, ms));
}
function clamp(n, lo, hi) {
    return Math.max(lo, Math.min(hi, n));
}
function randInt(lo, hi) {
    return Math.floor(lo + Math.random() * (hi - lo + 1));
}
// Box–Muller gaussian
function randn() {
    let u = 0;
    let v = 0;
    while (u === 0)
        u = Math.random();
    while (v === 0)
        v = Math.random();
    return Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
}
function pickRegime() {
    // weights: mostly calm, sometimes active, rarely panic
    const r = Math.random();
    if (r < 0.72)
        return "calm";
    if (r < 0.95)
        return "active";
    return "panic";
}
function regimeVolMult(regime) {
    if (regime === "calm")
        return 1.0;
    if (regime === "active")
        return 2.6;
    return 5.2; // panic
}
function tradeProb(regime) {
    if (regime === "calm")
        return 0.28;
    if (regime === "active")
        return 0.60;
    return 0.82;
}
function loopSleepMs(regime) {
    if (regime === "calm")
        return 450 + Math.random() * 900;
    if (regime === "active")
        return 160 + Math.random() * 550;
    return 80 + Math.random() * 220;
}
function qtyFor(symbol) {
    // keep BTC small, RVAI-ish bigger
    if (symbol.startsWith("BTC"))
        return (Math.random() * 0.05 + 0.005).toFixed(8);
    return (Math.random() * 0.22 + 0.01).toFixed(8);
}
async function fetchCoinbaseMid(productId) {
    const r = await fetch(`https://api.exchange.coinbase.com/products/${encodeURIComponent(productId)}/ticker`, {
        headers: {
            "user-agent": "dcapx-botfarm",
            accept: "application/json",
        },
    });
    if (!r.ok) {
        throw new Error(`coinbase ticker ${productId} -> ${r.status}`);
    }
    const j = await r.json();
    const bid = Number(j.bid);
    const ask = Number(j.ask);
    const price = Number(j.price);
    const mid = Number.isFinite(bid) && Number.isFinite(ask) && bid > 0 && ask > 0
        ? (bid + ask) / 2
        : price;
    if (!Number.isFinite(mid) || mid <= 0) {
        throw new Error(`bad ticker payload for ${productId}`);
    }
    return {
        mid,
        bid: Number.isFinite(bid) ? bid : mid,
        ask: Number.isFinite(ask) ? ask : mid,
        ts: Date.now(),
    };
}
async function startBtcOracleAgent() {
    console.log("[botFarm] BTC oracle agent starting...");
    while (true) {
        try {
            oracle["BTC-USD"] = await fetchCoinbaseMid("BTC-USD");
        }
        catch (e) {
            console.error("[botFarm] BTC oracle agent", e);
        }
        await sleep(5000);
    }
}
async function startBotFarm() {
    console.log("[botFarm] starting...");
    // Prime the oracle once immediately so BTC does not start too far off-market
    try {
        oracle["BTC-USD"] = await fetchCoinbaseMid("BTC-USD");
        console.log("[botFarm] BTC oracle primed", oracle["BTC-USD"]);
    }
    catch (e) {
        console.error("[botFarm] BTC oracle prime failed", e);
    }
    void startBtcOracleAgent();
    const markets = await prisma.market.findMany();
    const users = await prisma.user.findMany({ select: { id: true } });
    if (!markets.length || users.length < 2) {
        console.log("[botFarm] needs markets + at least 2 users");
        return;
    }
    // init per-symbol state from last trade (or midpoint / oracle)
    const state = {};
    const now = Date.now();
    for (const m of markets) {
        const symbol = m.symbol;
        const cfg = BANDS[symbol];
        const lo = cfg?.min ?? 0.00000001;
        const hi = cfg?.max ?? 10_000_000;
        const last = await prisma.trade.findFirst({
            where: { symbol, mode: client_1.TradeMode.PAPER },
            orderBy: { createdAt: "desc" },
            select: { price: true },
        });
        const oracleMid = symbol === "BTC-USD" && oracle["BTC-USD"]
            ? oracle["BTC-USD"].mid
            : undefined;
        const fallback = oracleMid ?? (cfg ? (cfg.min + cfg.max) / 2 : 100);
        const seeded = last ? Number(last.price) : fallback;
        const mid0 = clamp(seeded, lo, hi);
        const regime = pickRegime();
        const durSec = cfg ? randInt(cfg.regimeMinSec, cfg.regimeMaxSec) : 60;
        state[symbol] = {
            mid: mid0,
            anchor: mid0,
            volPct: cfg?.driftPct ?? 0.0015,
            momentum: 0,
            regime,
            regimeUntilMs: now + durSec * 1000,
        };
    }
    while (true) {
        const m = markets[Math.floor(Math.random() * markets.length)];
        const symbol = m.symbol;
        const cfg = BANDS[symbol];
        // tick handling
        const tickDb = Number(m.tickSize || 0.01);
        const tick = cfg?.tickOverride ?? tickDb ?? 0.01;
        const baseLo = cfg?.min ?? tick * 10;
        const baseHi = cfg?.max ?? 10_000_000;
        // ensure state exists
        if (!state[symbol]) {
            state[symbol] = {
                mid: clamp((baseLo + baseHi) / 2, baseLo, baseHi),
                anchor: clamp((baseLo + baseHi) / 2, baseLo, baseHi),
                volPct: cfg?.driftPct ?? 0.0015,
                momentum: 0,
                regime: "calm",
                regimeUntilMs: Date.now() + 60_000,
            };
        }
        const s = state[symbol];
        const tNow = Date.now();
        const live = oracle[symbol];
        const liveFresh = !!live && tNow - live.ts < 20_000;
        // range handling
        let lo = baseLo;
        let hi = baseHi;
        // For BTC, dynamically center the synthetic market around the live market
        if (symbol === "BTC-USD" && liveFresh) {
            s.anchor = s.anchor * 0.82 + live.mid * 0.18;
            s.mid = s.mid * 0.9 + live.mid * 0.1;
            lo = Math.max(baseLo, live.mid * 0.96);
            hi = Math.min(baseHi, live.mid * 1.04);
        }
        const range = Math.max(hi - lo, tick * 100);
        // roll regimes in blocks => volatility clustering (more realistic)
        if (cfg && tNow > s.regimeUntilMs) {
            s.regime = pickRegime();
            s.regimeUntilMs =
                tNow + randInt(cfg.regimeMinSec, cfg.regimeMaxSec) * 1000;
        }
        const volMult = cfg ? regimeVolMult(s.regime) : 1;
        // --- anchor random walk (this kills the sine-wave look) ---
        if (cfg) {
            const anchorStep = randn() * range * cfg.anchorNoisePct * (0.10 * volMult);
            s.anchor = clamp(s.anchor + anchorStep, lo, hi);
        }
        // --- volatility updates (clusters) ---
        if (cfg) {
            // mean-revert volatility to baseline, but let it breathe
            const baseline = cfg.driftPct;
            const target = baseline * (0.55 + 0.65 * volMult);
            s.volPct = clamp(s.volPct * 0.84 + target * 0.16, baseline * 0.25, baseline * 10);
            // tiny random “breathing”
            s.volPct *= 1 + Math.abs(randn()) * 0.03;
        }
        // --- momentum (short trends + chop) ---
        const momCap = tick * (cfg?.wickTicks ?? 8) * 1.2;
        s.momentum = clamp(s.momentum * 0.86 + randn() * tick * (cfg?.wickTicks ?? 8) * 0.04 * volMult, -momCap, momCap);
        // --- mid update: OU mean reversion + gaussian + momentum ---
        let mid = s.mid;
        // gaussian pct noise
        mid = mid * (1 + randn() * (s.volPct ?? 0.0015));
        // pull toward anchor (mean reversion)
        if (cfg)
            mid = mid + (s.anchor - mid) * cfg.pullToAnchor;
        // add momentum
        mid = mid + s.momentum;
        // --- rare jump shocks (news-like spikes) ---
        if (cfg) {
            const jumpP = cfg.jumpProb * (s.regime === "panic" ? 1.7 : 1.0);
            if (Math.random() < jumpP) {
                const sign = Math.random() < 0.5 ? -1 : 1;
                const jumpTicks = randInt(cfg.jumpTicksMin, cfg.jumpTicksMax) *
                    (s.regime === "panic" ? 2 : 1);
                mid = mid + sign * tick * jumpTicks;
                // also tug anchor slightly in the jump direction to create follow-through
                s.anchor = clamp(s.anchor + sign * range * 0.06, lo, hi);
            }
        }
        // clamp to band
        mid = clamp(mid, lo, hi);
        s.mid = mid;
        // --- CLEAN stale OPEN orders so your book doesn't stay crossed forever ---
        // Delete OPEN buys above mid and OPEN sells below mid (stale, crossed-looking)
        // (This is what makes your “best bid > best ask” issue disappear over time.)
        const midStr = mid.toFixed(8);
        await prisma.order.deleteMany({
            where: {
                symbol,
                mode: client_1.TradeMode.PAPER,
                status: client_1.OrderStatus.OPEN,
                OR: [
                    { side: client_1.OrderSide.BUY, price: { gt: midStr } },
                    { side: client_1.OrderSide.SELL, price: { lt: midStr } },
                ],
            },
        });
        // Also delete really old OPEN orders (keeps the book “fresh”)
        await prisma.order.deleteMany({
            where: {
                symbol,
                mode: client_1.TradeMode.PAPER,
                status: client_1.OrderStatus.OPEN,
                createdAt: { lt: new Date(Date.now() - 5 * 60 * 1000) }, // 5 minutes
            },
        });
        // --- place some OPEN depth around mid ---
        const maker1 = users[Math.floor(Math.random() * users.length)].id;
        let maker2 = users[Math.floor(Math.random() * users.length)].id;
        if (maker2 === maker1 && users.length > 1) {
            maker2 = users[(users.findIndex((u) => u.id === maker1) + 1) % users.length].id;
        }
        const levels = s.regime === "panic" ? 4 : s.regime === "active" ? 3 : 2;
        const openOrders = [];
        for (let i = 1; i <= levels; i++) {
            const skew = (Math.random() * 0.8 + 0.2) * tick; // small randomness
            const bid = clamp(mid - tick * i - skew, lo, hi);
            const ask = clamp(mid + tick * i + skew, lo, hi);
            openOrders.push({
                mode: client_1.TradeMode.PAPER,
                symbol,
                side: client_1.OrderSide.BUY,
                price: bid.toFixed(8),
                qty: qtyFor(symbol),
                status: client_1.OrderStatus.OPEN,
                userId: maker1,
            });
            openOrders.push({
                mode: client_1.TradeMode.PAPER,
                symbol,
                side: client_1.OrderSide.SELL,
                price: ask.toFixed(8),
                qty: qtyFor(symbol),
                status: client_1.OrderStatus.OPEN,
                userId: maker2,
            });
        }
        if (openOrders.length) {
            await prisma.order.createMany({ data: openOrders });
        }
        // --- print trades (this creates candle bodies + wicks) ---
        if (Math.random() < tradeProb(s.regime)) {
            const buyer = users[Math.floor(Math.random() * users.length)].id;
            let seller = users[Math.floor(Math.random() * users.length)].id;
            if (seller === buyer && users.length > 1) {
                seller = users[(users.findIndex((u) => u.id === buyer) + 1) % users.length].id;
            }
            const qty = qtyFor(symbol);
            const wick = (cfg?.wickTicks ?? 8) *
                (s.regime === "calm" ? 0.55 : s.regime === "active" ? 0.95 : 1.35);
            // gaussian around mid produces more natural candles than uniform/sine
            let pxNum = mid + randn() * tick * wick;
            // occasional wick-out inside the candle
            const wickOutP = s.regime === "panic" ? 0.18 : s.regime === "active" ? 0.10 : 0.06;
            if (Math.random() < wickOutP) {
                pxNum += randn() * tick * wick * 2.2;
            }
            pxNum = clamp(pxNum, lo, hi);
            const px = pxNum.toFixed(8);
            const buy = await prisma.order.create({
                data: {
                    mode: client_1.TradeMode.PAPER,
                    symbol,
                    side: client_1.OrderSide.BUY,
                    price: px,
                    qty,
                    status: client_1.OrderStatus.FILLED,
                    userId: buyer,
                },
                select: { id: true },
            });
            const sell = await prisma.order.create({
                data: {
                    mode: client_1.TradeMode.PAPER,
                    symbol,
                    side: client_1.OrderSide.SELL,
                    price: px,
                    qty,
                    status: client_1.OrderStatus.FILLED,
                    userId: seller,
                },
                select: { id: true },
            });
            await prisma.trade.create({
                data: {
                    mode: client_1.TradeMode.PAPER,
                    symbol,
                    price: px,
                    qty,
                    buyOrderId: buy.id,
                    sellOrderId: sell.id,
                },
            });
            // nudge mid toward last print (more realistic)
            s.mid = clamp(s.mid * 0.75 + pxNum * 0.25, lo, hi);
        }
        // --- trim growth (PAPER only) ---
        const OPEN_LIMIT = symbol === "RVAI-USD" ? 120 : 200;
        const TRADE_LIMIT = symbol === "RVAI-USD" ? 9000 : 12000;
        const openCount = await prisma.order.count({
            where: { symbol, mode: client_1.TradeMode.PAPER, status: client_1.OrderStatus.OPEN },
        });
        if (openCount > OPEN_LIMIT) {
            const olds = await prisma.order.findMany({
                where: { symbol, mode: client_1.TradeMode.PAPER, status: client_1.OrderStatus.OPEN },
                orderBy: { createdAt: "asc" },
                take: openCount - OPEN_LIMIT,
                select: { id: true },
            });
            await prisma.order.deleteMany({
                where: { id: { in: olds.map((o) => o.id) } },
            });
        }
        const tradeCount = await prisma.trade.count({
            where: { symbol, mode: client_1.TradeMode.PAPER },
        });
        if (tradeCount > TRADE_LIMIT) {
            const olds = await prisma.trade.findMany({
                where: { symbol, mode: client_1.TradeMode.PAPER },
                orderBy: { createdAt: "asc" },
                take: tradeCount - TRADE_LIMIT,
                select: { id: true },
            });
            await prisma.trade.deleteMany({
                where: { id: { in: olds.map((t) => t.id) } },
            });
        }
        await sleep(loopSleepMs(s.regime));
    }
}
