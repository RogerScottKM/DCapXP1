import { emitMatchingEvent, getMatchingEventCount, listMatchingEvents } from "../matching/matching-events";
import { getSerializedLaneCount } from "../matching/serialized-dispatch";

type ReconciliationResultLike = {
  check: string;
  ok: boolean;
  details?: Record<string, unknown>;
};

type RuntimeStatusState = {
  started: boolean;
  startedAt: string | null;
  stoppedAt: string | null;
  stopReason: string | null;
  port: number | null;
  reconciliationEnabled: boolean;
  reconciliationIntervalMs: number | null;
  lastReconciliationAt: string | null;
  lastReconciliationOk: boolean | null;
  lastReconciliationFailureCount: number;
  lastReconciliationCheckCount: number;
};

const runtimeState: RuntimeStatusState = {
  started: false,
  startedAt: null,
  stoppedAt: null,
  stopReason: null,
  port: null,
  reconciliationEnabled: false,
  reconciliationIntervalMs: null,
  lastReconciliationAt: null,
  lastReconciliationOk: null,
  lastReconciliationFailureCount: 0,
  lastReconciliationCheckCount: 0,
};

export type RuntimeStatusSnapshot = RuntimeStatusState & {
  activeSerializedLanes: number;
  matchingEventCount: number;
  lastEventId: number | null;
};

function snapshot(): RuntimeStatusSnapshot {
  const recentEvents = listMatchingEvents(1000);
  return {
    ...runtimeState,
    activeSerializedLanes: getSerializedLaneCount(),
    matchingEventCount: getMatchingEventCount(),
    lastEventId: recentEvents.length > 0 ? recentEvents[recentEvents.length - 1]!.id : null,
  };
}

export function markRuntimeStarted(input: {
  port: number;
  reconciliationEnabled: boolean;
  reconciliationIntervalMs: number;
}): RuntimeStatusSnapshot {
  runtimeState.started = true;
  runtimeState.startedAt = new Date().toISOString();
  runtimeState.stoppedAt = null;
  runtimeState.stopReason = null;
  runtimeState.port = input.port;
  runtimeState.reconciliationEnabled = input.reconciliationEnabled;
  runtimeState.reconciliationIntervalMs = input.reconciliationIntervalMs;

  const current = snapshot();
  emitMatchingEvent({
    type: "RUNTIME_STATUS",
    ts: new Date().toISOString(),
    symbol: "__SYSTEM__",
    mode: "SYSTEM",
    engine: "SYSTEM",
    source: "SYSTEM",
    payload: {
      status: "STARTED",
      runtime: current,
    },
  });
  return snapshot();
}

export function markRuntimeStopped(reason: string): RuntimeStatusSnapshot {
  runtimeState.started = false;
  runtimeState.stoppedAt = new Date().toISOString();
  runtimeState.stopReason = reason;

  const current = snapshot();
  emitMatchingEvent({
    type: "RUNTIME_STATUS",
    ts: new Date().toISOString(),
    symbol: "__SYSTEM__",
    mode: "SYSTEM",
    engine: "SYSTEM",
    source: "SYSTEM",
    payload: {
      status: "STOPPED",
      reason,
      runtime: current,
    },
  });
  return snapshot();
}

export function noteReconciliationRun(results: ReconciliationResultLike[]): RuntimeStatusSnapshot {
  const failures = results.filter((result) => !result.ok);

  runtimeState.lastReconciliationAt = new Date().toISOString();
  runtimeState.lastReconciliationOk = failures.length === 0;
  runtimeState.lastReconciliationFailureCount = failures.length;
  runtimeState.lastReconciliationCheckCount = results.length;

  const current = snapshot();
  emitMatchingEvent({
    type: "RECONCILIATION_RESULT",
    ts: runtimeState.lastReconciliationAt,
    symbol: "__SYSTEM__",
    mode: "SYSTEM",
    engine: "SYSTEM",
    source: "SYSTEM",
    payload: {
      ok: runtimeState.lastReconciliationOk,
      failureCount: runtimeState.lastReconciliationFailureCount,
      checkCount: runtimeState.lastReconciliationCheckCount,
      failures: failures.slice(0, 10),
      runtime: current,
    },
  });

  return snapshot();
}

export function getRuntimeStatus(): RuntimeStatusSnapshot {
  return snapshot();
}

export function resetRuntimeStatusForTests(): void {
  runtimeState.started = false;
  runtimeState.startedAt = null;
  runtimeState.stoppedAt = null;
  runtimeState.stopReason = null;
  runtimeState.port = null;
  runtimeState.reconciliationEnabled = false;
  runtimeState.reconciliationIntervalMs = null;
  runtimeState.lastReconciliationAt = null;
  runtimeState.lastReconciliationOk = null;
  runtimeState.lastReconciliationFailureCount = 0;
  runtimeState.lastReconciliationCheckCount = 0;
}
