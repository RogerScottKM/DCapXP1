// apps/api/src/infra/bus.ts
import { EventEmitter } from "node:events";
import type { TradeMode } from "./mode";

export type BookKey = { symbol: string; mode: TradeMode };

// If you use "*" for broadcast, model it explicitly:
export type SymbolKey = { symbol: string }; // symbol can be "*" where relevant

export type BusEvents = {
  trade: BookKey;
  orderbook: BookKey;

  // monitoring / control-plane signals
  symbolMode: SymbolKey;   // kill-switch/control changed for a symbol
  flags: SymbolKey;        // symbol OR "*" for global refresh
  riskLimits: SymbolKey;   // symbol OR "*" for refresh
};

// Strict typed surface (removes the untyped overloads)
type StrictTypedBus = Omit<EventEmitter, "on" | "once" | "off" | "emit"> & {
  on<K extends keyof BusEvents>(event: K, listener: (payload: BusEvents[K]) => void): StrictTypedBus;
  once<K extends keyof BusEvents>(event: K, listener: (payload: BusEvents[K]) => void): StrictTypedBus;
  off<K extends keyof BusEvents>(event: K, listener: (payload: BusEvents[K]) => void): StrictTypedBus;
  emit<K extends keyof BusEvents>(event: K, payload: BusEvents[K]): boolean;
};

export const bus: StrictTypedBus = new EventEmitter() as any;
bus.setMaxListeners(0);
