import { dbMatchingEngine } from "./db-matching-engine";
import { inMemoryMatchingEngine } from "./in-memory-matching-engine";
import type { MatchingEnginePort } from "./engine-port";

export type MatchingEngineSelection = "db" | "in_memory" | "DB_MATCHER" | "IN_MEMORY_MATCHER";

export function selectMatchingEngine(
  preferred?: MatchingEngineSelection | null,
): MatchingEnginePort {
  const selected = String(preferred ?? process.env.MATCHING_ENGINE ?? "db").trim();

  if (selected === "in_memory" || selected === "IN_MEMORY_MATCHER") {
    return inMemoryMatchingEngine;
  }

  return dbMatchingEngine;
}
