import { Decimal } from "@prisma/client/runtime/library";
import { type OrderSide } from "@prisma/client";

type Decimalish = string | number | Decimal;

export type PrioritySortableMaker = {
  price: Decimalish;
  createdAt: Date | string | number;
};

function toDecimal(value: Decimalish): Decimal {
  return value instanceof Decimal ? value : new Decimal(value);
}

function toTimestamp(value: Date | string | number): number {
  if (value instanceof Date) return value.getTime();
  return new Date(value).getTime();
}

export function buildMakerOrderByForTaker(side: OrderSide) {
  return side === "BUY"
    ? [{ price: "asc" as const }, { createdAt: "asc" as const }]
    : [{ price: "desc" as const }, { createdAt: "asc" as const }];
}

export function compareMakerPriority(
  takerSide: OrderSide,
  a: PrioritySortableMaker,
  b: PrioritySortableMaker,
): number {
  const priceA = toDecimal(a.price);
  const priceB = toDecimal(b.price);

  if (!priceA.eq(priceB)) {
    if (takerSide === "BUY") {
      return priceA.lessThan(priceB) ? -1 : 1;
    }
    return priceA.greaterThan(priceB) ? -1 : 1;
  }

  const tsA = toTimestamp(a.createdAt);
  const tsB = toTimestamp(b.createdAt);

  if (tsA < tsB) return -1;
  if (tsA > tsB) return 1;
  return 0;
}

export function sortMakersForTaker<T extends PrioritySortableMaker>(
  takerSide: OrderSide,
  makers: T[],
): T[] {
  return [...makers].sort((a, b) => compareMakerPriority(takerSide, a, b));
}
