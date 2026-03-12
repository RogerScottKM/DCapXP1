import type { UIPlanRequest, Persona, Intent, Widget } from "@repo/schema/ui";

export type PlanContext = {
  req: UIPlanRequest;
  persona: Persona;
  intent: Intent;
  symbol: string;
};

export type WidgetCandidate = {
  id: string;
  priority: number;
  colSpan: 1 | 2 | 3;
  build: (ctx: PlanContext) => unknown; // validated at the end by WidgetSchema
  when?: (ctx: PlanContext) => boolean;
};

