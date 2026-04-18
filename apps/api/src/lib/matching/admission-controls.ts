import { Decimal } from "@prisma/client/runtime/library";

export class AdmissionControlError extends Error {
  readonly status = 429;
  readonly code = "ADMISSION_CONTROL_REJECTED";

  constructor(message: string) {
    super(message);
    this.name = "AdmissionControlError";
  }
}

type WindowState = {
  timestamps: number[];
};

const orderWindowState = new Map<string, WindowState>();

function parseCsvList(value?: string | null): string[] {
  return String(value ?? "")
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
}

function getEnvNumber(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function resetAdmissionControlCountersForTests(): void {
  orderWindowState.clear();
}

export function computePriceDeviationBps(
  referencePrice: string | number | Decimal,
  submittedPrice: string | number | Decimal,
): Decimal {
  const reference = new Decimal(referencePrice);
  const submitted = new Decimal(submittedPrice);

  if (reference.lte(0)) return new Decimal(0);

  return submitted
    .minus(reference)
    .abs()
    .div(reference)
    .mul(10000);
}

export function assertWithinPriceBand(input: {
  referencePrice: string | number | Decimal;
  submittedPrice: string | number | Decimal;
  maxDeviationBps: number;
  symbol: string;
}): void {
  if (input.maxDeviationBps <= 0) return;

  const deviation = computePriceDeviationBps(input.referencePrice, input.submittedPrice);
  if (deviation.gt(input.maxDeviationBps)) {
    throw new AdmissionControlError(
      `Price band exceeded for ${input.symbol}: ${deviation.toFixed(2)}bps > ${input.maxDeviationBps}bps`,
    );
  }
}

export function assertSymbolEnabled(input: {
  symbol: string;
  marketEnabled?: boolean | null;
  disabledSymbols?: string[];
}): void {
  const disabled = new Set((input.disabledSymbols ?? []).map((value) => value.trim()).filter(Boolean));
  if (input.marketEnabled === false || disabled.has(input.symbol)) {
    throw new AdmissionControlError(`Trading disabled for ${input.symbol}`);
  }
}

export function consumeSlidingWindowLimit(input: {
  key: string;
  limit: number;
  windowMs?: number;
  nowMs?: number;
}): { used: number; remaining: number } {
  const windowMs = input.windowMs ?? 60_000;
  const nowMs = input.nowMs ?? Date.now();

  if (input.limit <= 0) {
    return { used: 0, remaining: Number.MAX_SAFE_INTEGER };
  }

  const existing = orderWindowState.get(input.key) ?? { timestamps: [] };
  existing.timestamps = existing.timestamps.filter((ts) => ts > nowMs - windowMs);

  if (existing.timestamps.length >= input.limit) {
    throw new AdmissionControlError(
      `Rate limit exceeded for ${input.key}: ${existing.timestamps.length}/${input.limit} in ${windowMs}ms`,
    );
  }

  existing.timestamps.push(nowMs);
  orderWindowState.set(input.key, existing);

  return {
    used: existing.timestamps.length,
    remaining: Math.max(0, input.limit - existing.timestamps.length),
  };
}

export async function enforceAdmissionControls(input: {
  db: any;
  userId: string;
  symbol: string;
  mode: string;
  price: string;
}): Promise<void> {
  const disabledSymbols = parseCsvList(process.env.MATCH_DISABLED_SYMBOLS);
  const maxDeviationBps = getEnvNumber("MATCH_MAX_PRICE_DEVIATION_BPS", 1500);
  const userOrderLimit = getEnvNumber("MATCH_MAX_ORDERS_PER_MINUTE_PER_USER", 60);
  const symbolOrderLimit = getEnvNumber("MATCH_MAX_ORDERS_PER_MINUTE_PER_SYMBOL", 600);

  let marketRecord: any = null;
  const marketRepo = input.db?.market;
  if (marketRepo?.findUnique) {
    marketRecord = await marketRepo.findUnique({ where: { symbol: input.symbol } });
  } else if (marketRepo?.findFirst) {
    marketRecord = await marketRepo.findFirst({ where: { symbol: input.symbol } });
  }

  assertSymbolEnabled({
    symbol: input.symbol,
    marketEnabled: marketRecord?.enabled,
    disabledSymbols,
  });

  const tradeRepo = input.db?.trade;
  const latestTrade =
    tradeRepo?.findFirst
      ? await tradeRepo.findFirst({
          where: {
            symbol: input.symbol,
            mode: input.mode,
          },
          orderBy: { id: "desc" },
        })
      : null;

  if (latestTrade?.price != null) {
    assertWithinPriceBand({
      referencePrice: latestTrade.price,
      submittedPrice: input.price,
      maxDeviationBps,
      symbol: input.symbol,
    });
  }

  consumeSlidingWindowLimit({
    key: `user:${input.userId}:${input.symbol}:${input.mode}`,
    limit: userOrderLimit,
  });

  consumeSlidingWindowLimit({
    key: `symbol:${input.symbol}:${input.mode}`,
    limit: symbolOrderLimit,
  });
}
