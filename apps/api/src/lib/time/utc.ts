export function toUtcIso(date: Date | null | undefined): string | null { return date ? date.toISOString() : null; }
