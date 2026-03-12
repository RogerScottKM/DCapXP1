// PAPER-ONLY demo bot: generates synthetic prints for UI testing.
// Will EXIT if MODE is not PAPER.

const API = process.env.API_URL || "http://127.0.0.1:4010";
const MODE = (process.env.MODE || "PAPER").toUpperCase();
const SYMBOLS = (process.env.SYMBOLS || "RVAI-USD,BTC-USD").split(",").map(s => s.trim()).filter(Boolean);

// Use two demo users (make sure these userIds exist in your DB)
const MAKER_UID = Number(process.env.MAKER_UID || 2);
const TAKER_UID = Number(process.env.TAKER_UID || 3);

if (MODE !== "PAPER") {
  console.error(`❌ Refusing to run: MODE must be PAPER (got ${MODE}).`);
  process.exit(1);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function postOrder(body) {
  const r = await fetch(`${API}/v1/orders`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const txt = await r.text();
  let j;
  try { j = JSON.parse(txt); } catch { j = { ok: false, error: txt }; }
  if (!r.ok || j?.ok === false) {
    throw new Error(`order failed ${r.status}: ${j?.error || txt}`);
  }
  return j;
}

// Sine-wave + small random noise inside [min,max]
function targetPrice({ min, max, periodMs, noisePct }) {
  const mid = (min + max) / 2;
  const amp = (max - min) / 2;
  const t = Date.now();
  const phase = (t % periodMs) / periodMs * Math.PI * 2;
  const base = mid + amp * Math.sin(phase);
  const noise = base * (noisePct * (Math.random() * 2 - 1));
  const p = base + noise;
  return Math.max(min, Math.min(max, p));
}

// Round to tick
function roundToTick(p, tick) {
  const n = Math.round(p / tick) * tick;
  return Number(n.toFixed(10));
}

const CFG = {
  "RVAI-USD": { min: 0.87, max: 1.39, tick: 0.0001, qty: 25, periodMs: 90_000, noisePct: 0.004 },
  // BTC defaults (override with env if you want)
  "BTC-USD":  {
    min: Number(process.env.BTC_MIN || 62000),
    max: Number(process.env.BTC_MAX || 69000),
    tick: Number(process.env.BTC_TICK || 0.01),
    qty: Number(process.env.BTC_QTY || 0.002),
    periodMs: Number(process.env.BTC_PERIOD_MS || 120_000),
    noisePct: Number(process.env.BTC_NOISE_PCT || 0.002),
  },
};

async function makePrint(symbol) {
  const cfg = CFG[symbol];
  if (!cfg) return;

  // Build 5 prints around a moving target to create wicks
  const center = targetPrice(cfg);
  const offsets = [-2, -1, 0, 1, 2].map((k) => k * (cfg.tick * 30)); // widen wicks
  const prices = offsets
    .map((off) => roundToTick(center + off, cfg.tick))
    .map((p) => Math.max(cfg.min, Math.min(cfg.max, p)));

  // Print sequence: SELL then BUY at same price to match immediately
  for (const p of prices) {
    const qty = cfg.qty;

    // maker sell
    await postOrder({
      userId: MAKER_UID,
      mode: MODE,
      symbol,
      side: "SELL",
      type: "LIMIT",
      price: p,
      qty,
    });

    // taker buy crosses to match the sell
    await postOrder({
      userId: TAKER_UID,
      mode: MODE,
      symbol,
      side: "BUY",
      type: "LIMIT",
      price: p,
      qty,
    });

    await sleep(150); // spread prints slightly
  }

  console.log(`✅ prints: ${symbol} center~${center.toFixed(6)} range=[${cfg.min},${cfg.max}]`);
}

async function loop() {
  const intervalMs = Number(process.env.INTERVAL_MS || 15_000); // 15s
  console.log(`🚀 demo_volatility_bot running (MODE=${MODE}) interval=${intervalMs}ms API=${API}`);
  console.log(`Symbols: ${SYMBOLS.join(", ")} | MAKER_UID=${MAKER_UID} TAKER_UID=${TAKER_UID}`);

  while (true) {
    try {
      for (const s of SYMBOLS) await makePrint(s);
    } catch (e) {
      console.error("❌", e?.message || e);
    }
    await sleep(intervalMs);
  }
}

loop().catch((e) => {
  console.error("FATAL", e);
  process.exit(1);
});
