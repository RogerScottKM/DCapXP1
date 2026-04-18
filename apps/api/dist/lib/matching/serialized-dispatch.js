"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.runSerializedByKey = runSerializedByKey;
exports.buildSymbolModeKey = buildSymbolModeKey;
exports.getSerializedLaneCount = getSerializedLaneCount;
exports.resetSerializedDispatchForTests = resetSerializedDispatchForTests;
const lanes = new Map();
async function runSerializedByKey(key, taskFactory) {
    const previous = lanes.get(key) ?? Promise.resolve();
    const run = previous.catch(() => undefined).then(taskFactory);
    const tracked = run.finally(() => {
        if (lanes.get(key) === tracked) {
            lanes.delete(key);
        }
    });
    lanes.set(key, tracked);
    return tracked;
}
function buildSymbolModeKey(symbol, mode) {
    return `${symbol}:${mode}`;
}
function getSerializedLaneCount() {
    return lanes.size;
}
function resetSerializedDispatchForTests() {
    lanes.clear();
}
