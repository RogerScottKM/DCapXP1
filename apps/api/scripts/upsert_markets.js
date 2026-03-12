const { PrismaClient, Prisma } = require("@prisma/client");
const prisma = new PrismaClient();

const MARKETS = [
  { symbol: "RVAI-USD", baseAsset: "RVAI", quoteAsset: "USD", tickSize: "0.0001", lotSize: "0.01"  },
  { symbol: "XAU-USD",  baseAsset: "XAU",  quoteAsset: "USD", tickSize: "0.01",   lotSize: "0.001" },
  { symbol: "EUR-USD",  baseAsset: "EUR",  quoteAsset: "USD", tickSize: "0.0001", lotSize: "1"     },
  { symbol: "AAPL-USD", baseAsset: "AAPL", quoteAsset: "USD", tickSize: "0.01",   lotSize: "1"     },
];

const D = (v) => new Prisma.Decimal(String(v));

async function main() {
  for (const m of MARKETS) {
    await prisma.market.upsert({
      where: { symbol: m.symbol },
      update: {
        baseAsset: m.baseAsset,
        quoteAsset: m.quoteAsset,
        tickSize: D(m.tickSize),
        lotSize: D(m.lotSize),
      },
      create: {
        symbol: m.symbol,
        baseAsset: m.baseAsset,
        quoteAsset: m.quoteAsset,
        tickSize: D(m.tickSize),
        lotSize: D(m.lotSize),
      },
    });

    console.log("✅ upsert:", m.symbol);
  }

  const rows = await prisma.market.findMany({ orderBy: { symbol: "asc" } });

  console.table(
    rows.map((r) => ({
      symbol: r.symbol,
      baseAsset: r.baseAsset,
      quoteAsset: r.quoteAsset,
      tickSize: String(r.tickSize),
      lotSize: String(r.lotSize),
    }))
  );
}

main()
  .catch((e) => {
    console.error("❌", e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
