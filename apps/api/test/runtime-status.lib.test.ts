import { beforeEach, describe, expect, it } from "vitest";

import { listMatchingEvents, resetMatchingEventsForTests } from "../src/lib/matching/matching-events";
import { resetSerializedDispatchForTests } from "../src/lib/matching/serialized-dispatch";
import {
  markRuntimeStarted,
  markRuntimeStopped,
  noteReconciliationRun,
  resetRuntimeStatusForTests,
} from "../src/lib/runtime/runtime-status";

describe("runtime status library", () => {
  beforeEach(() => {
    resetMatchingEventsForTests();
    resetSerializedDispatchForTests();
    resetRuntimeStatusForTests();
  });

  it("tracks runtime start and stop with status snapshots", () => {
    const started = markRuntimeStarted({
      port: 4010,
      reconciliationEnabled: true,
      reconciliationIntervalMs: 60000,
    });

    expect(started.started).toBe(true);
    expect(started.port).toBe(4010);
    expect(started.reconciliationEnabled).toBe(true);
    expect(started.matchingEventCount).toBe(1);

    const stopped = markRuntimeStopped("SIGTERM");

    expect(stopped.started).toBe(false);
    expect(stopped.stopReason).toBe("SIGTERM");
    expect(stopped.matchingEventCount).toBe(2);

    const eventTypes = listMatchingEvents().map((event) => event.type);
    expect(eventTypes).toEqual(["RUNTIME_STATUS", "RUNTIME_STATUS"]);
  });

  it("records reconciliation summaries and emits a reconciliation runtime event", () => {
    markRuntimeStarted({
      port: 4010,
      reconciliationEnabled: true,
      reconciliationIntervalMs: 60000,
    });

    const status = noteReconciliationRun([
      { check: "GLOBAL_BALANCE", ok: true },
      { check: "ORDER_STATUS_CONSISTENCY", ok: false, details: { mismatch: 1 } },
    ]);

    expect(status.lastReconciliationOk).toBe(false);
    expect(status.lastReconciliationFailureCount).toBe(1);
    expect(status.lastReconciliationCheckCount).toBe(2);

    const events = listMatchingEvents();
    expect(events[events.length - 1]?.type).toBe("RECONCILIATION_RESULT");
  });
});
