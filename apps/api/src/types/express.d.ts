import "express";

type TradeMode = "PAPER" | "LIVE";

declare global {
  namespace Express {
    interface Request {
      ctx?: {
        user: { id: string; username: string };
        mode: TradeMode;
      };
      auth?: any;
      userId?: string;
    }
  }
}

export {};
