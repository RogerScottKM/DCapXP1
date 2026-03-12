export const userStatusValues = [
  "INVITED",
  "REGISTERED",
  "OTP_VERIFIED",
  "ACTIVE",
  "SUSPENDED",
  "CLOSED",
] as const;

export const roleCodeValues = [
  "USER",
  "ADVISOR",
  "COMPLIANCE",
  "ADMIN",
  "AUDITOR",
  "PARTNER_ADMIN",
  "BANK_OPERATOR",
  "SYSTEM_AGENT",
] as const;

export const otpPurposeValues = [
  "REGISTER",
  "VERIFY_EMAIL",
  "VERIFY_PHONE",
  "LOGIN",
  "MFA",
  "RESET_PASSWORD",
] as const;

export const otpChannelValues = ["EMAIL", "SMS"] as const;

export const mfaFactorTypeValues = ["TOTP"] as const;
export const mfaFactorStatusValues = ["PENDING", "ACTIVE", "REVOKED"] as const;

export const kycStatusValues = ["PENDING", "APPROVED", "REJECTED"] as const;

export const kycCaseStatusValues = [
  "NOT_STARTED",
  "IN_PROGRESS",
  "SUBMITTED",
  "UNDER_REVIEW",
  "NEEDS_INFO",
  "APPROVED",
  "REJECTED",
  "EXPIRED",
] as const;

export const kycDocumentTypeValues = [
  "PASSPORT",
  "NATIONAL_ID",
  "DRIVER_LICENSE",
  "SELFIE",
  "PROOF_OF_ADDRESS",
  "BUSINESS_REGISTRATION",
  "OTHER",
] as const;

export const kycDecisionCodeValues = ["APPROVE", "REJECT", "REQUEST_INFO"] as const;

export const paymentMethodTypeValues = [
  "BANK_ACCOUNT",
  "STRIPE_CUSTOMER",
  "PAYPAL_ACCOUNT",
  "VENMO_ACCOUNT",
  "OTHER",
] as const;

export const paymentMethodStatusValues = [
  "ADDED",
  "PENDING_VERIFICATION",
  "VERIFIED",
  "RESTRICTED",
  "DISABLED",
] as const;

export const walletTypeValues = ["CUSTODIAL", "EXTERNAL"] as const;

export const walletStatusValues = [
  "CREATED",
  "PENDING_VERIFICATION",
  "WHITELISTED",
  "COOLDOWN",
  "ACTIVE",
  "FROZEN",
  "REVOKED",
] as const;

export const partnerOrgTypeValues = [
  "ADVISORY_FIRM",
  "BANK",
  "ISSUER",
  "EMPLOYER",
  "OTHER",
] as const;

export const assessmentRunStatusValues = [
  "PENDING",
  "RUNNING",
  "COMPLETED",
  "FAILED",
] as const;

export const aptivioProfileStatusValues = [
  "DRAFT",
  "ASSESSMENT_PENDING",
  "ACTIVE",
  "RESTRICTED",
  "ARCHIVED",
] as const;

export const agentCredentialTypeValues = ["PUBLIC_KEY", "API_KEY"] as const;

export const agentCapabilityTierValues = [
  "READ_ONLY",
  "RECOMMEND_ONLY",
  "PLAN_ONLY",
  "EXECUTE_TRADE",
] as const;

export const agentPrincipalTypeValues = [
  "DIGITAL_TWIN",
  "TRADING_AGENT",
  "COMPLIANCE_AGENT",
  "ADVISOR_AGENT",
  "INTERNAL_MM",
] as const;

export const agentStatusValues = ["DRAFT", "ACTIVE", "PAUSED", "REVOKED"] as const;

export const agentKindValues = [
  "RISK_GUARD",
  "MARKET_MAKER",
  "SCALPER",
  "MEAN_REVERT",
  "TREND_FOLLOW",
  "DCA",
  "NEWS_SENTIMENT",
  "ARBITRAGE",
  "PORTFOLIO_MANAGER",
] as const;

export const mandateActionValues = ["TRADE", "WITHDRAW", "TRANSFER"] as const;

export const mandateStatusValues = ["ACTIVE", "REVOKED", "EXPIRED"] as const;

export const twinTierValues = ["WHALE", "TRADER", "SCALPER", "LEARNER", "NEWBIE"] as const;

export const tradeModeValues = ["PAPER", "LIVE"] as const;
