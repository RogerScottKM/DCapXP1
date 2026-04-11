import { Decimal } from "@prisma/client/runtime/library";
import type { LedgerPostingSide } from "@prisma/client";

export type PostingSide = LedgerPostingSide | "DEBIT" | "CREDIT";

export type PostingInput = {
  accountId: string;
  assetCode: string;
  side: PostingSide;
  amount: string | number | Decimal;
};

export type NormalizedPosting = {
  accountId: string;
  assetCode: string;
  side: "DEBIT" | "CREDIT";
  amount: Decimal;
};

export function toDecimal(value: string | number | Decimal): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

export function normalizePostings(postings: PostingInput[]): NormalizedPosting[] {
  return postings.map((posting) => {
    const accountId = String(posting.accountId ?? "").trim();
    const assetCode = String(posting.assetCode ?? "").trim().toUpperCase();
    const side = posting.side === "CREDIT" ? "CREDIT" : "DEBIT";
    const amount = toDecimal(posting.amount);

    if (!accountId) {
      throw new Error("Ledger posting accountId is required.");
    }
    if (!assetCode) {
      throw new Error("Ledger posting assetCode is required.");
    }
    if (amount.lte(0)) {
      throw new Error("Ledger posting amount must be greater than zero.");
    }

    return { accountId, assetCode, side, amount };
  });
}

export function assertBalancedPostings(postings: PostingInput[]): NormalizedPosting[] {
  if (postings.length < 2) {
    throw new Error("Ledger transaction must include at least two postings.");
  }

  const normalized = normalizePostings(postings);
  const grouped = new Map<string, { debit: Decimal; credit: Decimal }>();

  for (const posting of normalized) {
    const current = grouped.get(posting.assetCode) ?? {
      debit: new Decimal(0),
      credit: new Decimal(0),
    };

    if (posting.side === "DEBIT") {
      current.debit = current.debit.plus(posting.amount);
    } else {
      current.credit = current.credit.plus(posting.amount);
    }

    grouped.set(posting.assetCode, current);
  }

  for (const [assetCode, totals] of grouped.entries()) {
    if (!totals.debit.eq(totals.credit)) {
      throw new Error(`Ledger postings are not balanced for asset ${assetCode}.`);
    }
  }

  return normalized;
}

export function buildLedgerTransfer(params: {
  fromAccountId: string;
  toAccountId: string;
  assetCode: string;
  amount: string | number | Decimal;
}): PostingInput[] {
  const amount = toDecimal(params.amount);
  if (amount.lte(0)) {
    throw new Error("Ledger transfer amount must be greater than zero.");
  }

  return [
    {
      accountId: params.fromAccountId,
      assetCode: params.assetCode,
      side: "CREDIT",
      amount,
    },
    {
      accountId: params.toAccountId,
      assetCode: params.assetCode,
      side: "DEBIT",
      amount,
    },
  ];
}
