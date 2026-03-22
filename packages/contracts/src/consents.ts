import type { UtcIsoString } from "./common";
export type ConsentType = "TERMS_OF_SERVICE" | "PRIVACY_POLICY" | "DATA_PROCESSING" | "ELECTRONIC_COMMUNICATION" | "APTIVIO_ASSESSMENT_AUTH" | "ADVISOR_DATA_SHARING_CONSENT";
export interface RequiredConsentItem { consentType: ConsentType; version: string; label: string; required: boolean; }
export interface GetRequiredConsentsResponse { items: RequiredConsentItem[]; missingConsentTypes: ConsentType[]; }
export interface AcceptConsentsRequest { items: Array<{ consentType: ConsentType; version: string; }>; }
export interface ConsentRecordDto { consentType: ConsentType; version: string; acceptedAtUtc: UtcIsoString; revokedAtUtc: UtcIsoString | null; }
