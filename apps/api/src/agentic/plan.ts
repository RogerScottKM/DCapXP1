import { UIPlanRequestSchema, UIPlanSchema } from "@repo/schema/ui";
import type { UIPlan } from "@repo/schema/ui";
import { inferPersona } from "./persona";
import { widgetCandidates } from "./widgets";

export function generateUIPlan(input: unknown): UIPlan {
  const req = UIPlanRequestSchema.parse(input);

  const persona = inferPersona(req.userId);
  const intent = req.intent;
  const symbol = req.symbol;

  const ctx = { req, persona, intent, symbol };

  const layout = widgetCandidates
    .filter((c) => (c.when ? c.when(ctx) : true))
    .sort((a, b) => a.priority - b.priority)
    .map((c) => ({
      id: c.id,
      priority: c.priority,
      colSpan: c.colSpan,
      widget: c.build(ctx),
    }));

  return UIPlanSchema.parse({
    version: "1.0",
    generatedFor: { userId: req.userId, persona, intent, symbol },
    layout,
  });
}
