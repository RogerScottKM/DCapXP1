"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.tradeModeValues = exports.twinTierValues = exports.mandateStatusValues = exports.mandateActionValues = exports.agentKindValues = exports.agentStatusValues = exports.agentPrincipalTypeValues = exports.agentCapabilityTierValues = exports.agentCredentialTypeValues = exports.aptivioProfileStatusValues = exports.assessmentRunStatusValues = exports.partnerOrgTypeValues = exports.walletStatusValues = exports.walletTypeValues = exports.paymentMethodStatusValues = exports.paymentMethodTypeValues = exports.kycDecisionCodeValues = exports.kycDocumentTypeValues = exports.kycCaseStatusValues = exports.kycStatusValues = exports.mfaFactorStatusValues = exports.mfaFactorTypeValues = exports.otpChannelValues = exports.otpPurposeValues = exports.roleCodeValues = exports.userStatusValues = void 0;
exports.userStatusValues = [
    "INVITED",
    "REGISTERED",
    "OTP_VERIFIED",
    "ACTIVE",
    "SUSPENDED",
    "CLOSED",
];
exports.roleCodeValues = [
    "USER",
    "ADVISOR",
    "COMPLIANCE",
    "ADMIN",
    "AUDITOR",
    "PARTNER_ADMIN",
    "BANK_OPERATOR",
    "SYSTEM_AGENT",
];
exports.otpPurposeValues = [
    "REGISTER",
    "VERIFY_EMAIL",
    "VERIFY_PHONE",
    "LOGIN",
    "MFA",
    "RESET_PASSWORD",
];
exports.otpChannelValues = ["EMAIL", "SMS"];
exports.mfaFactorTypeValues = ["TOTP"];
exports.mfaFactorStatusValues = ["PENDING", "ACTIVE", "REVOKED"];
exports.kycStatusValues = ["PENDING", "APPROVED", "REJECTED"];
exports.kycCaseStatusValues = [
    "NOT_STARTED",
    "IN_PROGRESS",
    "SUBMITTED",
    "UNDER_REVIEW",
    "NEEDS_INFO",
    "APPROVED",
    "REJECTED",
    "EXPIRED",
];
exports.kycDocumentTypeValues = [
    "PASSPORT",
    "NATIONAL_ID",
    "DRIVER_LICENSE",
    "SELFIE",
    "PROOF_OF_ADDRESS",
    "BUSINESS_REGISTRATION",
    "OTHER",
];
exports.kycDecisionCodeValues = ["APPROVE", "REJECT", "REQUEST_INFO"];
exports.paymentMethodTypeValues = [
    "BANK_ACCOUNT",
    "STRIPE_CUSTOMER",
    "PAYPAL_ACCOUNT",
    "VENMO_ACCOUNT",
    "OTHER",
];
exports.paymentMethodStatusValues = [
    "ADDED",
    "PENDING_VERIFICATION",
    "VERIFIED",
    "RESTRICTED",
    "DISABLED",
];
exports.walletTypeValues = ["CUSTODIAL", "EXTERNAL"];
exports.walletStatusValues = [
    "CREATED",
    "PENDING_VERIFICATION",
    "WHITELISTED",
    "COOLDOWN",
    "ACTIVE",
    "FROZEN",
    "REVOKED",
];
exports.partnerOrgTypeValues = [
    "ADVISORY_FIRM",
    "BANK",
    "ISSUER",
    "EMPLOYER",
    "OTHER",
];
exports.assessmentRunStatusValues = [
    "PENDING",
    "RUNNING",
    "COMPLETED",
    "FAILED",
];
exports.aptivioProfileStatusValues = [
    "DRAFT",
    "ASSESSMENT_PENDING",
    "ACTIVE",
    "RESTRICTED",
    "ARCHIVED",
];
exports.agentCredentialTypeValues = ["PUBLIC_KEY", "API_KEY"];
exports.agentCapabilityTierValues = [
    "READ_ONLY",
    "RECOMMEND_ONLY",
    "PLAN_ONLY",
    "EXECUTE_TRADE",
];
exports.agentPrincipalTypeValues = [
    "DIGITAL_TWIN",
    "TRADING_AGENT",
    "COMPLIANCE_AGENT",
    "ADVISOR_AGENT",
    "INTERNAL_MM",
];
exports.agentStatusValues = ["DRAFT", "ACTIVE", "PAUSED", "REVOKED"];
exports.agentKindValues = [
    "RISK_GUARD",
    "MARKET_MAKER",
    "SCALPER",
    "MEAN_REVERT",
    "TREND_FOLLOW",
    "DCA",
    "NEWS_SENTIMENT",
    "ARBITRAGE",
    "PORTFOLIO_MANAGER",
];
exports.mandateActionValues = ["TRADE", "WITHDRAW", "TRANSFER"];
exports.mandateStatusValues = ["ACTIVE", "REVOKED", "EXPIRED"];
exports.twinTierValues = ["WHALE", "TRADER", "SCALPER", "LEARNER", "NEWBIE"];
exports.tradeModeValues = ["PAPER", "LIVE"];
