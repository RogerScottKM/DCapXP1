// apps/api/prisma/seed.ts
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

const ISSUER_CONTROLLED_ASSETS = new Set(["RVAI", "RVGX", "APTV"]);
const isIssuerControlled = (code: string) => ISSUER_CONTROLLED_ASSETS.has(code);

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

const APTITUDES = [
  ["cognitive_reasoning", "Cognitive Reasoning & Logic", "Cognitive & Problem-Solving"],
  ["problem_decomposition", "Problem Decomposition", "Cognitive & Problem-Solving"],
  ["systems_thinking", "Systems Thinking", "Cognitive & Problem-Solving"],
  ["learning_velocity", "Learning Velocity", "Cognitive & Problem-Solving"],
  ["situational_judgment", "Situational Judgment", "Cognitive & Problem-Solving"],

  ["domain_knowledge", "Domain Knowledge", "Technical / Domain Mastery"],
  ["tool_technology_proficiency", "Tool & Technology Proficiency", "Technical / Domain Mastery"],
  ["quality_precision_output", "Quality & Precision of Output", "Technical / Domain Mastery"],

  ["verbal_communication", "Verbal Communication", "Interpersonal & Communication"],
  ["written_communication", "Written Communication", "Interpersonal & Communication"],
  ["empathy_client_care", "Empathy & Client/Patient Care", "Interpersonal & Communication"],
  ["collaboration_teamwork", "Collaboration & Teamwork", "Interpersonal & Communication"],

  ["reliability_follow_through", "Reliability & Follow-Through", "Execution, Reliability & Professionalism"],
  ["attention_to_detail", "Attention to Detail", "Execution, Reliability & Professionalism"],
  ["time_management_prioritisation", "Time Management & Prioritisation", "Execution, Reliability & Professionalism"],
  ["process_discipline_compliance", "Process Discipline & Compliance", "Execution, Reliability & Professionalism"],
  ["ownership_accountability", "Ownership & Accountability", "Execution, Reliability & Professionalism"],

  ["adaptability_to_change", "Adaptability to Change", "Adaptability, Resilience & Growth"],
  ["stress_tolerance_emotional_regulation", "Stress Tolerance & Emotional Regulation", "Adaptability, Resilience & Growth"],
  ["feedback_responsiveness", "Feedback Responsiveness", "Adaptability, Resilience & Growth"],

  ["planning_coordination", "Planning & Coordination", "Leadership, Coordination & Influence"],
  ["coaching_mentoring", "Coaching & Mentoring", "Leadership, Coordination & Influence"],
  ["conflict_management", "Conflict Management", "Leadership, Coordination & Influence"],

  ["ethical_judgment_integrity", "Ethical Judgment & Integrity", "Ethics, Trust & Safety"],
  ["safety_risk_awareness", "Safety & Risk Awareness", "Ethics, Trust & Safety"],
] as const;

async function seedCatalog() {
  const assetCodes = Array.from(new Set(MARKETS.flatMap((m) => [m.base, m.quote])));

  for (const code of assetCodes) {
    await prisma.asset.upsert({
      where: { code },
      update: {
        kind: assetKind(code) as any,
        issuerControlled: isIssuerControlled(code),
      },
      create: {
        code,
        kind: assetKind(code) as any,
        issuerControlled: isIssuerControlled(code),
      },
    });
  }

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
    if (!base || !quote) throw new Error(`Missing asset for ${m.symbol}`);

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

async function seedAptitudes() {
  for (const [index, [slug, name, category]] of APTITUDES.entries()) {
    await prisma.aptitudeDefinition.upsert({
      where: { slug },
      update: {
        name,
        category,
        orderIndex: index + 1,
        isActive: true,
      },
      create: {
        slug,
        name,
        category,
        orderIndex: index + 1,
        isActive: true,
      },
    });
  }
}

async function main() {
  console.log("Seeding reference catalog...");
  await seedCatalog();

  console.log("Seeding Aptivio aptitude definitions...");
  await seedAptitudes();

  console.log("Reference seed complete ✅");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
