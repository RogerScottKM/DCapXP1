export function formatUtcForViewer(utcIsoString: string | null | undefined): string {
  if (!utcIsoString) return "—";

  const date = new Date(utcIsoString);
  if (Number.isNaN(date.getTime())) return "Invalid date";

  const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";

  return new Intl.DateTimeFormat("en-AU", {
    year: "numeric",
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
    timeZone,
    timeZoneName: "short",
  }).format(date);
}
