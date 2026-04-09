#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

FILE="apps/api/src/botFarm.ts"

if [ ! -f "$FILE" ]; then
  echo "Missing $FILE"
  exit 1
fi

cp "$FILE" "${FILE}.bak.$(date +%Y%m%d%H%M%S)}"

python3 - <<'PY'
from pathlib import Path
import re
import sys

path = Path("apps/api/src/botFarm.ts")
text = path.read_text()

# ------------------------------------------------------------
# 1) Calm RVAI config slightly for more realistic persisted history
# ------------------------------------------------------------
old_band = '''  "RVAI-USD": {
    min: Number(process.env.RVAI_MIN ?? 0.083),
    max: Number(process.env.RVAI_MAX ?? 0.12),

    tickOverride: Number(process.env.RVAI_TICK ?? 0.0001),

    // Much calmer intrabar behavior, still active enough to feel alive
    driftPct: 0.00135,
    wickTicks: 6,
    pullToAnchor: 0.065,
    anchorNoisePct: 0.0035,
    jumpProb: 0.006,
    jumpTicksMin: 6,
    jumpTicksMax: 22,

    regimeMinSec: 24,
    regimeMaxSec: 110,

    forceTradeEveryMs: 2400,

    openLevels: 4,
    openLimit: 160,
    tradeLimit: 9000,
    staleOpenMs: 90_000,
  },'''

new_band = '''  "RVAI-USD": {
    min: Number(process.env.RVAI_MIN ?? 0.083),
    max: Number(process.env.RVAI_MAX ?? 0.12),

    tickOverride: Number(process.env.RVAI_TICK ?? 0.0001),

    // Calmer synthetic profile with less exaggerated wick pressure
    driftPct: 0.00100,
    wickTicks: 5,
    pullToAnchor: 0.080,
    anchorNoisePct: 0.0024,
    jumpProb: 0.0045,
    jumpTicksMin: 4,
    jumpTicksMax: 14,

    regimeMinSec: 28,
    regimeMaxSec: 120,

    forceTradeEveryMs: 2600,

    openLevels: 4,
    openLimit: 180,
    tradeLimit: 12000,
    staleOpenMs: 90_000,
  },'''

if old_band not in text:
    print("Could not find exact RVAI band block.")
    sys.exit(1)

text = text.replace(old_band, new_band, 1)

# ------------------------------------------------------------
# 2) Insert historical seeding helpers before cleanupSymbolBook
# ------------------------------------------------------------
anchor = 'async function cleanupSymbolBook('
if anchor not in text:
    print("Could not find cleanupSymbolBook anchor.")
    sys.exit(1)

helper_block = '''
async function seedHistoricalFilledTrade(
  symbol: string,
  cfg: BandCfg,
  pxNum: number,
  at: Date,
  userIds: string[]
) {
  if (userIds.length < 2) return null;

  const [buyer, seller] = pickTwoDistinct(userIds);
  const qty = qtyFor(symbol);
  const px = clamp(pxNum, cfg.min, cfg.max).toFixed(8);

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
        createdAt: at,
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
        createdAt: at,
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
      createdAt: at,
    },
  });

  return Number(px);
}

async function ensureRvaiPaperHistory(
  symbol: string,
  cfg: BandCfg,
  userIds: string[]
) {
  if (symbol !== "RVAI-USD") return;
  if (userIds.length < 2) return;

  const targetSpanMs = Number(process.env.RVAI_HISTORY_SPAN_MS ?? 8 * 60 * 60 * 1000);
  const stepMs = Number(process.env.RVAI_HISTORY_STEP_MS ?? 30_000);
  const maxPoints = Number(process.env.RVAI_HISTORY_MAX_POINTS ?? 960);

  const now = Date.now();
  const desiredStartMs = now - targetSpanMs;

  const oldest = await prisma.trade.findFirst({
    where: { symbol, mode: TradeMode.PAPER },
    orderBy: { createdAt: "asc" },
    select: { price: true, createdAt: true },
  });

  const newest = await prisma.trade.findFirst({
    where: { symbol, mode: TradeMode.PAPER },
    orderBy: { createdAt: "desc" },
    select: { price: true, createdAt: true },
  });

  const oldestMs = oldest ? new Date(oldest.createdAt).getTime() : now;
  if (oldest && oldestMs <= desiredStartMs) {
    return;
  }

  const endMs = oldest ? oldestMs - stepMs : now - stepMs;
  const missingMs = endMs - desiredStartMs;
  if (missingMs <= 0) return;

  const points = Math.min(maxPoints, Math.ceil(missingMs / stepMs));
  if (points <= 0) return;

  let px = clamp(
    oldest
      ? Number(oldest.price)
      : newest
      ? Number(newest.price)
      : (cfg.min + cfg.max) / 2,
    cfg.min,
    cfg.max
  );

  let anchor = px;
  const tick = cfg.tickOverride ?? 0.0001;
  const range = Math.max(cfg.max - cfg.min, tick * 120);

  for (let i = points; i >= 1; i -= 1) {
    const at = new Date(endMs - (i - 1) * stepMs);

    const bandPos = (anchor - cfg.min) / range;
    const sweepBias = (0.5 - bandPos) * range * 0.010;
    const anchorStep = randn() * range * 0.0018 + sweepBias;

    anchor = clamp(anchor + anchorStep, cfg.min, cfg.max);

    px = px * (1 + randn() * 0.00085);
    px = px + (anchor - px) * 0.11;

    if (Math.random() < 0.012) {
      const sign = Math.random() < 0.5 ? -1 : 1;
      px += sign * tick * randInt(3, 9);
    }

    px = clamp(px, cfg.min, cfg.max);

    await seedHistoricalFilledTrade(symbol, cfg, px, at, userIds);
  }

  console.log(
    `[botFarm] RVAI historical PAPER seed inserted ${points} trades from ${new Date(
      endMs - (points - 1) * stepMs
    ).toISOString()} to ${new Date(endMs).toISOString()}`
  );
}

'''
text = text.replace(anchor, helper_block + '\n' + anchor, 1)

# ------------------------------------------------------------
# 3) Seed RVAI history before initState() in startSymbolWorker
# ------------------------------------------------------------
old_worker_start = '''async function startSymbolWorker(symbol: string, tickDb: number) {
  const cfg = BANDS[symbol];
  if (!cfg) return;

  await scrubPaperOutliers(symbol, cfg);

  const s = await initState(symbol, cfg);'''

new_worker_start = '''async function startSymbolWorker(symbol: string, tickDb: number) {
  const cfg = BANDS[symbol];
  if (!cfg) return;

  await scrubPaperOutliers(symbol, cfg);

  {
    const seedUsers = await getActiveUserIds();
    if (seedUsers.length >= 2) {
      await ensureRvaiPaperHistory(symbol, cfg, seedUsers);
    }
  }

  const s = await initState(symbol, cfg);'''

if old_worker_start not in text:
    print("Could not find startSymbolWorker init block.")
    sys.exit(1)

text = text.replace(old_worker_start, new_worker_start, 1)

# ------------------------------------------------------------
# 4) Tone down RVAI sweep bias / loop step / soft-center / trade wick deviations
# ------------------------------------------------------------
replacements = {
    '* range * 0.035;': '* range * 0.018;',
    'const maxStepAbs = 0.0022;': 'const maxStepAbs = 0.0012;',
    'mid = mid + (rvaiSoftCenter - mid) * 0.015;': 'mid = mid + (rvaiSoftCenter - mid) * 0.028;',
    '? cfg.wickTicks *\n      (regime === "calm" ? 0.16 : regime === "active" ? 0.24 : 0.34)': '? cfg.wickTicks *\n      (regime === "calm" ? 0.12 : regime === "active" ? 0.20 : 0.28)',
    'pxNum += randn() * tick * wick * (isRvai ? 0.55 : 2.2);': 'pxNum += randn() * tick * wick * (isRvai ? 0.45 : 2.2);',
    'const maxTradeDeviation = 0.0028;': 'const maxTradeDeviation = 0.0016;',
}

for old, new in replacements.items():
    if old in text:
        text = text.replace(old, new)

path.write_text(text)
print("Patched botFarm.ts")
PY

echo
echo "==> Quick verify"
rg -n 'RVAI_HISTORY|seedHistoricalFilledTrade|ensureRvaiPaperHistory|driftPct: 0.00100|wickTicks: 5|maxStepAbs = 0.0012|maxTradeDeviation = 0.0016' "$FILE" || true

echo
echo "==> Type/build check"
pnpm --filter api build

echo
echo "✅ RVAI backend history patch applied."
echo
echo "Next run:"
echo "  docker compose build api --no-cache"
echo "  docker compose up -d api"
echo
echo "Optional diagnostics after restart:"
echo "  docker compose logs api --tail=120"
echo '  curl -s "http://127.0.0.1:4010/api/v1/botfarm/status" | jq .'
