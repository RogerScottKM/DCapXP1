export type TradeMode = "PAPER" | "LIVE";

export type RequestContext = {
  user: { id: number; username: string };  // ✅ number (Prisma Int)
  mode: TradeMode;
};
