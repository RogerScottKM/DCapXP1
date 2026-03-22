export type UtcIsoString = string;
export interface ApiErrorResponse {
  error: { code: string; message: string; fieldErrors?: Record<string, string>; retryable?: boolean; details?: unknown; };
}
