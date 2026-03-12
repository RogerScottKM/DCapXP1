// apps/api/prisma/seed-demo-bootstrap.ts
import {
  PrismaClient,
  UserStatus,
  RoleCode,
  KycStatus,
  KycCaseStatus,
  KycDecisionCode,
  PaymentMethodType,
  PaymentMethodStatus,
  WalletType,
  WalletStatus,
  AptivioProfileStatus,
  AssessmentRunStatus,
  AgentStatus,
  AgentKind,
  AgentPrincipalType,
  AgentCapabilityTier,
  AgentCredentialType,
  MandateAction,
  MandateStatus,
  TradeMode,
  OrderSide,
  OrderStatus,
  TwinTier,
  PartnerOrgType,
  MfaFactorType,
  MfaFactorStatus,
} from "@prisma/client";

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

function assetKind(code: string) {
  if (["USD", "EUR", "JPY", "AUD"].includes(code)) return "FIAT";
  if (["XAU", "XAG"].includes(code)) return "COMMODITY";
  if (["RVAI", "RVGX", "APTV"].includes(code)) return "TOKEN";
  return "CRYPTO";
}

function tierPlan(tier: TwinTier, symbols: string[], rng: () => number) {
  const riskPct =
    tier === TwinTier.WHALE
      ? randFloat(rng, 0.001, 0.008)
      : tier === TwinTier.TRADER
      ? randFloat(rng, 0.005, 0.02)
      : tier === TwinTier.SCALPER
      ? randFloat(rng, 0.002, 0.01)
      : tier === TwinTier.LEARNER
      ? randFloat(rng, 0.002, 0.008)
      : randFloat(rng, 0.001, 0.006);

  const maxOrders =
    tier === TwinTier.WHALE
      ? randInt(rng, 50, 200)
      : tier === TwinTier.TRADER
      ? randInt(rng, 80, 250)
      : tier === TwinTier.SCALPER
      ? randInt(rng, 150, 600)
      : tier === TwinTier.LEARNER
      ? randInt(rng, 20, 80)
      : randInt(rng, 10, 60);

  return {
    riskPct,
    maxOrdersPerDay: maxOrders,
    preferredSymbols: symbols,
    plan: {
      mode: "PAPER",
      tier,
      allowedSymbols: symbols,
      risk: {
        perTradePct: riskPct,
        dailyMaxOrders: maxOrders,
        maxSlippageBps: tier === TwinTier.SCALPER ? 5 : 20,
        fatFingerBands: true,
      },
      behavior: {
        style:
          tier === TwinTier.WHALE
            ? "patient-liquidity"
            : tier === TwinTier.SCALPER
            ? "micro-mean-revert"
            : tier === TwinTier.TRADER
            ? "trend-pullback"
            : tier === TwinTier.LEARNER
            ? "guided-sim"
            : "ultra-safe",
        timeframes: ["1m", "5m", "1h", "1d"],
      },
      coaching: {
        enabled: true,
        tone: tier === TwinTier.LEARNER || tier === TwinTier.NEWBIE ? "teaching" : "concise",
      },
    },
  };
}

async function resetDemoData() {
  console.log("Destructive demo reset via TRUNCATE...");

  await prisma.$executeRawUnsafe(`
    TRUNCATE TABLE
      "AssessmentAptitudeScore",
      "AssessmentRun",
      "AptivioIdentity",
      "AptivioProfile",
      "AdvisorClientAssignment",
      "AdvisorProfile",
      "PartnerOrganization",
      "WalletWhitelistEntry",
      "Wallet",
      "BankAccount",
      "PaymentMethod",
      "ScreeningResult",
      "KycDecision",
      "KycDocument",
      "KycCase",
      "ConsentRecord",
      "RoleAssignment",
      "MfaFactor",
      "OtpChallenge",
      "Session",
      "UserProfile",
      "Trade",
      "Order",
      "Balance",
      "TwinAgentAssignment",
      "DigitalTwinProfile",
      "Kyc",
      "MandateUsage",
      "Mandate",
      "AgentKey",
      "RequestNonce",
      "Agent",
      "AuditEvent",
      "User",
      "Instrument",
      "Market",
      "Asset",
      "AptitudeDefinition"
    RESTART IDENTITY CASCADE;
  `);

  console.log("Destructive demo reset complete.");
}

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

async function createStaffUser(input: {
  email: string;
  username: string;
  firstName: string;
  lastName: string;
  phone: string;
  roles: RoleCode[];
  mfa?: boolean;
}) {
  const now = new Date();

  const user = await prisma.user.create({
    data: {
      email: input.email,
      username: input.username,
      phone: input.phone,
      passwordHash: "DEV_DEMO_ONLY_DO_NOT_USE_IN_PROD",
      totpSecret: input.mfa ? "DEMO_TOTP_SECRET" : null,
      status: UserStatus.ACTIVE,
      emailVerifiedAt: now,
      phoneVerifiedAt: now,
      profile: {
        create: {
          firstName: input.firstName,
          lastName: input.lastName,
          fullName: `${input.firstName} ${input.lastName}`,
          country: "AU",
          residency: "AU",
          nationality: "AU",
          sourceChannel: "demo-bootstrap",
        },
      },
      roles: {
        create: input.roles.map((role) => ({
          roleCode: role,
        })),
      },
      consents: {
        create: [
          { consentType: "terms", version: "v1.0" },
          { consentType: "privacy", version: "v1.0" },
        ],
      },
      mfaFactors: input.mfa
        ? {
            create: [
              {
                type: MfaFactorType.TOTP,
                status: MfaFactorStatus.ACTIVE,
                label: "Demo Authenticator",
                secretEncrypted: "DEMO_ENCRYPTED_SECRET",
                activatedAt: now,
              },
            ],
          }
        : undefined,
    },
    include: {
      profile: true,
      roles: true,
    },
  });

  await prisma.auditEvent.create({
    data: {
      actorType: "SYSTEM",
      action: "USER_REGISTERED",
      resourceType: "User",
      resourceId: user.id,
      metadata: {
        email: user.email,
        username: user.username,
        seeded: true,
      },
    },
  });

  return user;
}

async function seedPartnersAndStaff() {
  const advisoryFirm = await prisma.partnerOrganization.create({
    data: {
      name: "DCapX Advisory Partners",
      type: PartnerOrgType.ADVISORY_FIRM,
      country: "AU",
      metadata: {
        seeded: true,
      },
    },
  });

  const bankPartner = await prisma.partnerOrganization.create({
    data: {
      name: "Agribank Pilot",
      type: PartnerOrgType.BANK,
      country: "VN",
      metadata: {
        seeded: true,
      },
    },
  });

  const houseUser = await createStaffUser({
    email: "house@dcapx.local",
    username: "house",
    firstName: "House",
    lastName: "System",
    phone: "+15550000001",
    roles: [RoleCode.SYSTEM_AGENT, RoleCode.ADMIN],
    mfa: true,
  });

  const adminUser = await createStaffUser({
    email: "admin@dcapx.local",
    username: "admin",
    firstName: "Admin",
    lastName: "Operator",
    phone: "+15550000002",
    roles: [RoleCode.ADMIN],
    mfa: true,
  });

  const complianceUser = await createStaffUser({
    email: "compliance@dcapx.local",
    username: "compliance",
    firstName: "Compliance",
    lastName: "Reviewer",
    phone: "+15550000003",
    roles: [RoleCode.COMPLIANCE],
    mfa: true,
  });

  const advisorUser = await createStaffUser({
    email: "advisor@dcapx.local",
    username: "advisor",
    firstName: "Ava",
    lastName: "Advisor",
    phone: "+15550000004",
    roles: [RoleCode.ADVISOR],
    mfa: true,
  });

  const bankRmUser = await createStaffUser({
    email: "agribank.rm@dcapx.local",
    username: "agribank_rm",
    firstName: "Bao",
    lastName: "Nguyen",
    phone: "+15550000005",
    roles: [RoleCode.BANK_OPERATOR],
    mfa: true,
  });

  await prisma.advisorProfile.create({
    data: {
      userId: advisorUser.id,
      organizationId: advisoryFirm.id,
      licenseNumber: "AFSL-DEMO-001",
      status: "ACTIVE",
      specialties: {
        wealth: true,
        digitalAssets: true,
        aptivio: true,
      },
    },
  });

  await prisma.auditEvent.createMany({
    data: [
      {
        actorType: "SYSTEM",
        action: "PARTNER_CREATED",
        resourceType: "PartnerOrganization",
        resourceId: advisoryFirm.id,
        metadata: { name: advisoryFirm.name },
      },
      {
        actorType: "SYSTEM",
        action: "PARTNER_CREATED",
        resourceType: "PartnerOrganization",
        resourceId: bankPartner.id,
        metadata: { name: bankPartner.name },
      },
    ],
  });

  return {
    houseUser,
    adminUser,
    complianceUser,
    advisorUser,
    bankRmUser,
    advisoryFirm,
    bankPartner,
  };
}

async function seedAgents(houseUserId: string) {
  const agents = [
    {
      name: "Aegis RiskGuard",
      kind: AgentKind.RISK_GUARD,
      principalType: AgentPrincipalType.COMPLIANCE_AGENT,
      capabilityTier: AgentCapabilityTier.PLAN_ONLY,
      role: "risk",
    },
    {
      name: "Atlas MarketMaker",
      kind: AgentKind.MARKET_MAKER,
      principalType: AgentPrincipalType.INTERNAL_MM,
      capabilityTier: AgentCapabilityTier.EXECUTE_TRADE,
      role: "primary",
    },
    {
      name: "Kite Scalper",
      kind: AgentKind.SCALPER,
      principalType: AgentPrincipalType.TRADING_AGENT,
      capabilityTier: AgentCapabilityTier.EXECUTE_TRADE,
      role: "primary",
    },
    {
      name: "Falcon TrendFollow",
      kind: AgentKind.TREND_FOLLOW,
      principalType: AgentPrincipalType.TRADING_AGENT,
      capabilityTier: AgentCapabilityTier.EXECUTE_TRADE,
      role: "primary",
    },
    {
      name: "Harbor DCA",
      kind: AgentKind.DCA,
      principalType: AgentPrincipalType.TRADING_AGENT,
      capabilityTier: AgentCapabilityTier.PLAN_ONLY,
      role: "primary",
    },
    {
      name: "Scribe NewsSentiment",
      kind: AgentKind.NEWS_SENTIMENT,
      principalType: AgentPrincipalType.ADVISOR_AGENT,
      capabilityTier: AgentCapabilityTier.RECOMMEND_ONLY,
      role: "copilot",
    },
    {
      name: "Crown PortfolioMgr",
      kind: AgentKind.PORTFOLIO_MANAGER,
      principalType: AgentPrincipalType.DIGITAL_TWIN,
      capabilityTier: AgentCapabilityTier.PLAN_ONLY,
      role: "primary",
    },
  ] as const;

  const created = [];

  for (const a of agents) {
    const agent = await prisma.agent.create({
      data: {
        userId: houseUserId,
        name: a.name,
        kind: a.kind,
        principalType: a.principalType,
        capabilityTier: a.capabilityTier,
        version: "1.0",
        status: AgentStatus.ACTIVE,
        config: {
          seeded: true,
          role: a.role,
        },
      },
    });

    await prisma.agentKey.create({
      data: {
        agentId: agent.id,
        credentialType: AgentCredentialType.PUBLIC_KEY,
        publicKeyPem: `-----BEGIN PUBLIC KEY-----
DEMO_${a.name.replace(/\s+/g, "_").toUpperCase()}
-----END PUBLIC KEY-----`,
      },
    });

    if (
      a.kind === AgentKind.MARKET_MAKER ||
      a.kind === AgentKind.SCALPER ||
      a.kind === AgentKind.TREND_FOLLOW ||
      a.kind === AgentKind.DCA ||
      a.kind === AgentKind.PORTFOLIO_MANAGER
    ) {
      const mandate = await prisma.mandate.create({
        data: {
          agentId: agent.id,
          status: MandateStatus.ACTIVE,
          action: MandateAction.TRADE,
          market: null,
          maxNotionalPerDay: BigInt("1000000000"),
          maxOrdersPerDay: 5000,
          notBefore: new Date(),
          expiresAt: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000),
          constraints: {
            tifAllowlist: ["GTC"],
            postOnly: false,
            maxSlippageBps: 50,
            seeded: true,
          },
        },
      });

      await prisma.mandateUsage.create({
        data: {
          mandateId: mandate.id,
          day: new Date(new Date().toISOString().slice(0, 10)),
          notionalUsed: BigInt(0),
          ordersPlaced: 0,
        },
      });
    }

    created.push(agent);

    await prisma.auditEvent.create({
      data: {
        actorType: "SYSTEM",
        action: "AGENT_CREATED",
        resourceType: "Agent",
        resourceId: agent.id,
        metadata: {
          name: agent.name,
          kind: agent.kind,
          principalType: agent.principalType,
          seeded: true,
        },
      },
    });
  }

  return created;
}

function buildAptitudeScores(
  tier: TwinTier,
  defs: { id: string; slug: string; name: string; category: string }[],
  rng: () => number,
) {
  return defs.map((d) => {
    const base =
      tier === TwinTier.WHALE
        ? randInt(rng, 72, 95)
        : tier === TwinTier.TRADER
        ? randInt(rng, 62, 88)
        : tier === TwinTier.SCALPER
        ? randInt(rng, 60, 86)
        : tier === TwinTier.LEARNER
        ? randInt(rng, 50, 78)
        : randInt(rng, 42, 70);

    const confidence = Number(randFloat(rng, 0.72, 0.96).toFixed(4));
    const weightForRole = Number(randFloat(rng, 0.4, 1.0).toFixed(4));

    return {
      aptitudeDefinitionId: d.id,
      slug: d.slug,
      name: d.name,
      category: d.category,
      score: base,
      confidence,
      weightForRole,
    };
  });
}

async function createDemoClient(input: {
  index: number;
  tier: TwinTier;
  complianceUserId: string;
  advisorUserId: string;
  agentRows: { id: string; kind: AgentKind }[];
  aptitudeDefs: { id: string; slug: string; name: string; category: string }[];
  rng: () => number;
}) {
  const { index, tier, complianceUserId, advisorUserId, agentRows, aptitudeDefs, rng } = input;

  const first = ["Alex", "Minh", "Dung", "Huy", "Linh", "Thao", "Peter", "An", "Khanh", "Mai"];
  const last = ["Nguyen", "Tran", "Le", "Pham", "Hoang", "Vu", "Do", "Bui", "Dang", "Phan"];
  const countries = ["VN", "AU", "UAE", "SG", "US", "GB"];

  const username = `twin_${String(index).padStart(3, "0")}_${String(tier).toLowerCase()}`;
  const email = `${username}@twins.dcapx.local`;
  const legalName = `${pick(rng, first)} ${pick(rng, last)}`;
  const [firstName, lastName] = legalName.split(" ");
  const country = pick(rng, countries);
  const phone = `+1555${String(100000 + index).slice(-6)}`;

  const preferred =
    tier === TwinTier.WHALE
      ? pick(rng, [
          ["BTC-USD", "ETH-USD", "XAU-USD", "RVAI-USD"],
          ["BTC-USD", "ETH-USD", "SOL-USD", "APTV-USD"],
          ["BTC-USD", "XAU-USD", "RVGX-USD"],
        ])
      : tier === TwinTier.SCALPER
      ? pick(rng, [
          ["BTC-USD", "ETH-USD"],
          ["BTC-USD", "XRP-USD"],
          ["ETH-USD", "SOL-USD"],
        ])
      : tier === TwinTier.TRADER
      ? pick(rng, [
          ["BTC-USD", "ETH-USD", "SOL-USD"],
          ["BTC-USD", "XAU-USD"],
          ["ETH-USD", "XRP-USD"],
        ])
      : tier === TwinTier.LEARNER
      ? pick(rng, [
          ["BTC-USD"],
          ["ETH-USD"],
          ["XAU-USD"],
          ["RVAI-USD"],
        ])
      : pick(rng, [["BTC-USD"], ["ETH-USD"], ["XRP-USD"]]);

  const twin = tierPlan(tier, preferred, rng);
  const aptitudeScores = buildAptitudeScores(tier, aptitudeDefs, rng);
  const overallScore = Math.round(
    aptitudeScores.reduce((sum, a) => sum + a.score, 0) / aptitudeScores.length,
  );

  const user = await prisma.user.create({
    data: {
      email,
      username,
      phone,
      passwordHash: "DEV_DEMO_ONLY_DO_NOT_USE_IN_PROD",
      totpSecret: null,
      status: UserStatus.ACTIVE,
      emailVerifiedAt: new Date(),
      phoneVerifiedAt: new Date(),

      profile: {
        create: {
          firstName,
          lastName: lastName ?? "User",
          fullName: legalName,
          dateOfBirth: new Date("1993-08-25T00:00:00.000Z"),
          country,
          residency: country,
          nationality: country,
          employerName: "Demo Client",
          sourceChannel: "demo-bootstrap",
        },
      },

      roles: {
        create: [{ roleCode: RoleCode.USER }],
      },

      consents: {
        create: [
          { consentType: "terms", version: "v1.0" },
          { consentType: "privacy", version: "v1.0" },
          { consentType: "aptivio", version: "v1.0" },
        ],
      },

      kyc: {
        create: {
          legalName,
          country,
          dob: new Date("1993-08-25T00:00:00.000Z"),
          docType: "PASSPORT",
          docHash: `demo:${username}:${Math.floor(rng() * 1e9)}`,
          status: KycStatus.APPROVED,
          riskScore: String((rng() * 3).toFixed(6)),
        },
      },
    },
    include: {
      profile: true,
    },
  });

  const kycCase = await prisma.kycCase.create({
    data: {
      userId: user.id,
      status: KycCaseStatus.APPROVED,
      notes: "Approved demo KYC case",
      startedAt: new Date(),
      submittedAt: new Date(),
      reviewedAt: new Date(),
      reviewerUserId: complianceUserId,
    },
  });

  await prisma.kycDocument.create({
    data: {
      kycCaseId: kycCase.id,
      docType: "PASSPORT",
      fileKey: `demo/kyc/${user.id}/passport.pdf`,
      fileName: "passport.pdf",
      mimeType: "application/pdf",
      metadata: {
        seeded: true,
      },
    },
  });

  await prisma.kycDecision.create({
    data: {
      kycCaseId: kycCase.id,
      decision: KycDecisionCode.APPROVE,
      reviewerUserId: complianceUserId,
      notes: "Demo approval",
    },
  });

  await prisma.screeningResult.create({
    data: {
      kycCaseId: kycCase.id,
      screeningType: "sanctions_pep",
      result: "clear",
      score: "0.0200",
      payload: {
        seeded: true,
      },
    },
  });

  const paymentMethod = await prisma.paymentMethod.create({
    data: {
      userId: user.id,
      type: PaymentMethodType.BANK_ACCOUNT,
      status: PaymentMethodStatus.VERIFIED,
      label: "Primary Bank Account",
      metadata: {
        seeded: true,
      },
      bankAccount: {
        create: {
          accountHolderName: legalName,
          bankName: country === "VN" ? "Agribank" : "Demo Bank",
          country,
          currency: "USD",
          maskedAccountNumber: `***${String(randInt(rng, 1000, 9999))}`,
          maskedRoutingNumber: `***${String(randInt(rng, 1000, 9999))}`,
        },
      },
    },
    include: { bankAccount: true },
  });

  const custodialWallet = await prisma.wallet.create({
    data: {
      userId: user.id,
      type: WalletType.CUSTODIAL,
      status: WalletStatus.ACTIVE,
      label: "DCapX Custodial Wallet",
      isCustodial: true,
      activatedAt: new Date(),
      verifiedAt: new Date(),
      metadata: {
        seeded: true,
      },
    },
  });

  const externalAddress = `0x${String(index).padStart(40, "0")}`;

  await prisma.wallet.create({
    data: {
      userId: user.id,
      type: WalletType.EXTERNAL,
      status: WalletStatus.ACTIVE,
      chain: "ETH",
      address: externalAddress,
      label: "Whitelisted External Wallet",
      isCustodial: false,
      activatedAt: new Date(),
      verifiedAt: new Date(),
      metadata: {
        seeded: true,
      },
    },
  });

  await prisma.walletWhitelistEntry.create({
    data: {
      userId: user.id,
      chain: "ETH",
      address: externalAddress,
      label: "Primary Whitelist",
      status: WalletStatus.ACTIVE,
      approvedAt: new Date(),
    },
  });

  const aptivioProfile = await prisma.aptivioProfile.create({
    data: {
      userId: user.id,
      status: AptivioProfileStatus.ACTIVE,
      score: overallScore,
      aptitudeVector: aptitudeScores.map((a) => ({
        id: a.slug,
        name: a.name,
        score: a.score,
        confidence: a.confidence,
        weightForRole: a.weightForRole,
      })),
      twinJson: {
        context: {
          fullName: legalName,
          primaryRole: tier === TwinTier.WHALE ? "Portfolio Manager" : "Retail Trader",
          roleFamily: "Wealth",
          seniority: tier === TwinTier.WHALE ? "senior" : "mid",
          country,
          sourceSystem: "demo-bootstrap",
        },
        metadata: {
          tags: [String(tier).toLowerCase(), "demo"],
          privacyLevel: "restricted",
          consentGiven: true,
        },
        tradingPlan: twin.plan,
      },
      skillPassportJson: {
        skills: [
          { name: "Financial Literacy", category: "Finance", level: 3 },
          { name: "Risk Awareness", category: "Finance", level: 3 },
          { name: "Platform Navigation", category: "Product", level: 4 },
        ],
        certifications: [],
      },
      professionalismJson: {
        overallScore: Math.min(100, overallScore + 3),
        lastUpdatedAt: new Date().toISOString(),
        signals: {
          reliability: Math.min(100, overallScore + 5),
          attendance: Math.min(100, overallScore + 2),
          documentationQuality: Math.max(55, overallScore - 4),
          clientFeedback: Math.min(100, overallScore + 1),
        },
      },
      trajectoryJson: {
        aptitudeTrend: "improving",
        skillGrowthRate: 0.12,
        window: "last_12_months",
      },
      riskProfileJson: {
        humanCapitalRiskScore: Number((rng() * 0.35).toFixed(2)),
        notes: "Seeded demo human-capital profile",
        assessedAt: new Date().toISOString(),
      },
      version: "v1.0.0",
      lastAssessedAt: new Date(),
    },
  });

  const assessmentRun = await prisma.assessmentRun.create({
    data: {
      userId: user.id,
      aptivioProfileId: aptivioProfile.id,
      assessmentType: "demo_seed_assessment",
      status: AssessmentRunStatus.COMPLETED,
      rawResultJson: { seeded: true },
      normalizedJson: { overallScore },
      startedAt: new Date(),
      completedAt: new Date(),
    },
  });

  await prisma.assessmentAptitudeScore.createMany({
    data: aptitudeScores.map((a) => ({
      assessmentRunId: assessmentRun.id,
      aptitudeDefinitionId: a.aptitudeDefinitionId,
      score: a.score,
      confidence: String(a.confidence),
      weightForRole: String(a.weightForRole),
      lastAssessedAt: new Date(),
      sourcesJson: [
        { type: "assessment", refId: `demo_assessment_${user.id}`, weight: 0.7 },
        { type: "simulation", refId: `demo_sim_${user.id}`, weight: 0.3 },
      ],
    })),
  });

  await prisma.aptivioIdentity.create({
    data: {
      aptivioProfileId: aptivioProfile.id,
      passportNumber: `APT-${String(index).padStart(6, "0")}`,
      status: "ACTIVE",
      claimsJson: {
        employabilityTier: tier,
        demo: true,
      },
      tokenEntitlementsJson: {
        twinEligible: true,
        tradingAgentEligible: tier !== TwinTier.NEWBIE,
      },
    },
  });

  await prisma.digitalTwinProfile.create({
    data: {
      userId: user.id,
      tier,
      riskPct: String(twin.riskPct.toFixed(6)),
      maxOrdersPerDay: twin.maxOrdersPerDay,
      preferredSymbols: twin.preferredSymbols,
      plan: twin.plan,
    },
  });

  const riskGuard = agentRows.find((a) => a.kind === AgentKind.RISK_GUARD);
  const copilot = agentRows.find((a) => a.kind === AgentKind.NEWS_SENTIMENT);

  const primary =
    tier === TwinTier.WHALE
      ? agentRows.find((a) => a.kind === AgentKind.PORTFOLIO_MANAGER)
      : tier === TwinTier.SCALPER
      ? agentRows.find((a) => a.kind === AgentKind.SCALPER)
      : tier === TwinTier.TRADER
      ? agentRows.find((a) => a.kind === AgentKind.TREND_FOLLOW)
      : agentRows.find((a) => a.kind === AgentKind.DCA);

  const assignments = [
    riskGuard ? { userId: user.id, agentId: riskGuard.id, role: "risk" } : null,
    primary ? { userId: user.id, agentId: primary.id, role: "primary" } : null,
    copilot ? { userId: user.id, agentId: copilot.id, role: "copilot" } : null,
  ].filter(Boolean) as { userId: string; agentId: string; role: string }[];

  if (assignments.length > 0) {
    await prisma.twinAgentAssignment.createMany({
      data: assignments,
      skipDuplicates: true,
    });
  }

  const usd =
    tier === TwinTier.WHALE
      ? randFloat(rng, 250_000, 5_000_000)
      : tier === TwinTier.TRADER
      ? randFloat(rng, 25_000, 250_000)
      : tier === TwinTier.SCALPER
      ? randFloat(rng, 10_000, 80_000)
      : tier === TwinTier.LEARNER
      ? randFloat(rng, 2_000, 15_000)
      : randFloat(rng, 500, 5_000);

  const btc = tier === TwinTier.WHALE ? randFloat(rng, 5, 60) : randFloat(rng, 0, 2);
  const eth = tier === TwinTier.WHALE ? randFloat(rng, 50, 800) : randFloat(rng, 0, 30);

  await prisma.balance.createMany({
    data: [
      { userId: user.id, asset: "USD", amount: usd.toFixed(6), mode: TradeMode.PAPER },
      { userId: user.id, asset: "BTC", amount: btc.toFixed(6), mode: TradeMode.PAPER },
      { userId: user.id, asset: "ETH", amount: eth.toFixed(6), mode: TradeMode.PAPER },
      { userId: user.id, asset: "RVAI", amount: randFloat(rng, 0, 50000).toFixed(6), mode: TradeMode.PAPER },
      { userId: user.id, asset: "RVGX", amount: randFloat(rng, 0, 20000).toFixed(6), mode: TradeMode.PAPER },
    ],
    skipDuplicates: true,
  });

  await prisma.advisorClientAssignment.create({
    data: {
      advisorUserId: advisorUserId,
      clientUserId: user.id,
      status: "ACTIVE",
      notes: `Seeded ${tier} client`,
    },
  });

  await prisma.auditEvent.createMany({
    data: [
      {
        actorType: "SYSTEM",
        action: "KYC_APPROVED",
        resourceType: "KycCase",
        resourceId: kycCase.id,
        metadata: { userId: user.id, seeded: true },
      },
      {
        actorType: "SYSTEM",
        action: "PAYMENT_METHOD_ADDED",
        resourceType: "PaymentMethod",
        resourceId: paymentMethod.id,
        metadata: { userId: user.id, seeded: true },
      },
      {
        actorType: "SYSTEM",
        action: "APTIVIO_ID_ISSUED",
        resourceType: "AptivioProfile",
        resourceId: aptivioProfile.id,
        metadata: { userId: user.id, seeded: true },
      },
    ],
  });

  return user;
}

async function seedClients(
  complianceUserId: string,
  advisorUserId: string,
  agentRows: { id: string; kind: AgentKind }[],
) {
  const rng = mulberry32(42);

  const aptitudeDefs = await prisma.aptitudeDefinition.findMany({
    orderBy: { orderIndex: "asc" },
    select: {
      id: true,
      slug: true,
      name: true,
      category: true,
    },
  });

  const tiers: { tier: TwinTier; count: number }[] = [
    { tier: TwinTier.WHALE, count: 3 },
    { tier: TwinTier.TRADER, count: 6 },
    { tier: TwinTier.SCALPER, count: 5 },
    { tier: TwinTier.LEARNER, count: 5 },
    { tier: TwinTier.NEWBIE, count: 5 },
  ];

  const clients = [];
  let idx = 1;

  for (const t of tiers) {
    for (let i = 0; i < t.count; i++) {
      const client = await createDemoClient({
        index: idx,
        tier: t.tier,
        complianceUserId,
        advisorUserId,
        agentRows,
        aptitudeDefs,
        rng,
      });
      clients.push(client);
      idx++;
    }
  }

  return clients;
}

async function seedInitialMarketState(clientIds: string[]) {
  const rng = mulberry32(99);
  if (clientIds.length < 4) throw new Error("Need demo clients to seed market state");

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

    const u1 = pick(rng, clientIds);
    const u2 = pick(rng, clientIds);

    await prisma.order.create({
      data: {
        mode: TradeMode.PAPER,
        symbol: m.symbol,
        side: OrderSide.BUY,
        price: (mid - tick).toFixed(8),
        qty: randFloat(rng, 0.5, 5).toFixed(8),
        status: OrderStatus.OPEN,
        userId: u1,
      },
    });

    await prisma.order.create({
      data: {
        mode: TradeMode.PAPER,
        symbol: m.symbol,
        side: OrderSide.SELL,
        price: (mid + tick).toFixed(8),
        qty: randFloat(rng, 0.5, 5).toFixed(8),
        status: OrderStatus.OPEN,
        userId: u2,
      },
    });

    const buy = await prisma.order.create({
      data: {
        mode: TradeMode.PAPER,
        symbol: m.symbol,
        side: OrderSide.BUY,
        price: (mid + tick).toFixed(8),
        qty: randFloat(rng, 0.05, 0.5).toFixed(8),
        status: OrderStatus.FILLED,
        userId: u1,
      },
    });

    const sell = await prisma.order.create({
      data: {
        mode: TradeMode.PAPER,
        symbol: m.symbol,
        side: OrderSide.SELL,
        price: (mid + tick).toFixed(8),
        qty: String(buy.qty),
        status: OrderStatus.FILLED,
        userId: u2,
      },
    });

    await prisma.trade.create({
      data: {
        mode: TradeMode.PAPER,
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
  await resetDemoData();

  console.log("Seeding reference catalog...");
  await seedCatalog();

  console.log("Seeding Aptivio definitions...");
  await seedAptitudes();

  console.log("Seeding partners and staff...");
  const staff = await seedPartnersAndStaff();

  console.log("Seeding house agents...");
  const agents = await seedAgents(staff.houseUser.id);

  console.log("Seeding demo clients...");
  const clients = await seedClients(
    staff.complianceUser.id,
    staff.advisorUser.id,
    agents.map((a) => ({ id: a.id, kind: a.kind })),
  );

  console.log("Seeding paper market state...");
  await seedInitialMarketState(clients.map((c) => c.id));

  console.log("Demo bootstrap complete ✅");
  console.log("Demo users:");
  console.log("  admin@dcapx.local / username: admin");
  console.log("  compliance@dcapx.local / username: compliance");
  console.log("  advisor@dcapx.local / username: advisor");
  console.log("  agribank.rm@dcapx.local / username: agribank_rm");
  console.log("  house@dcapx.local / username: house");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
