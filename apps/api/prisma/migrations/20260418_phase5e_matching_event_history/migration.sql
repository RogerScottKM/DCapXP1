-- Phase 5E durable event history
CREATE TABLE "MatchingEvent" (
  "id" BIGSERIAL PRIMARY KEY,
  "eventId" INTEGER NOT NULL UNIQUE,
  "type" TEXT NOT NULL,
  "ts" TIMESTAMP(3) NOT NULL,
  "symbol" TEXT NOT NULL,
  "mode" TEXT NOT NULL,
  "engine" TEXT NOT NULL,
  "source" TEXT NOT NULL,
  "payload" JSONB NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX "MatchingEvent_symbol_mode_eventId_idx"
  ON "MatchingEvent" ("symbol", "mode", "eventId");
