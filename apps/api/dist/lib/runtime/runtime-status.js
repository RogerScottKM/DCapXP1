"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.markRuntimeStarted = markRuntimeStarted;
exports.markRuntimeStopped = markRuntimeStopped;
exports.noteReconciliationRun = noteReconciliationRun;
exports.getRuntimeStatus = getRuntimeStatus;
exports.resetRuntimeStatusForTests = resetRuntimeStatusForTests;
const matching_events_1 = require("../matching/matching-events");
const serialized_dispatch_1 = require("../matching/serialized-dispatch");
const runtimeState = {
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
function snapshot() {
    const recentEvents = (0, matching_events_1.listMatchingEvents)(1000);
    return {
        ...runtimeState,
        activeSerializedLanes: (0, serialized_dispatch_1.getSerializedLaneCount)(),
        matchingEventCount: (0, matching_events_1.getMatchingEventCount)(),
        lastEventId: recentEvents.length > 0 ? recentEvents[recentEvents.length - 1].id : null,
    };
}
function markRuntimeStarted(input) {
    runtimeState.started = true;
    runtimeState.startedAt = new Date().toISOString();
    runtimeState.stoppedAt = null;
    runtimeState.stopReason = null;
    runtimeState.port = input.port;
    runtimeState.reconciliationEnabled = input.reconciliationEnabled;
    runtimeState.reconciliationIntervalMs = input.reconciliationIntervalMs;
    const current = snapshot();
    (0, matching_events_1.emitMatchingEvent)({
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
function markRuntimeStopped(reason) {
    runtimeState.started = false;
    runtimeState.stoppedAt = new Date().toISOString();
    runtimeState.stopReason = reason;
    const current = snapshot();
    (0, matching_events_1.emitMatchingEvent)({
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
function noteReconciliationRun(results) {
    const failures = results.filter((result) => !result.ok);
    runtimeState.lastReconciliationAt = new Date().toISOString();
    runtimeState.lastReconciliationOk = failures.length === 0;
    runtimeState.lastReconciliationFailureCount = failures.length;
    runtimeState.lastReconciliationCheckCount = results.length;
    const current = snapshot();
    (0, matching_events_1.emitMatchingEvent)({
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
function getRuntimeStatus() {
    return snapshot();
}
function resetRuntimeStatusForTests() {
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
