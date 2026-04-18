"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.emitMatchingEvent = emitMatchingEvent;
exports.emitMatchingEvents = emitMatchingEvents;
exports.persistMatchingEventEnvelope = persistMatchingEventEnvelope;
exports.persistMatchingEventEnvelopes = persistMatchingEventEnvelopes;
exports.listPersistedMatchingEvents = listPersistedMatchingEvents;
exports.listMatchingEvents = listMatchingEvents;
exports.getMatchingEventCount = getMatchingEventCount;
exports.subscribeMatchingEvents = subscribeMatchingEvents;
exports.getMatchingEventListenerCount = getMatchingEventListenerCount;
exports.resetMatchingEventsForTests = resetMatchingEventsForTests;
exports.buildMatchingEventsFromSubmission = buildMatchingEventsFromSubmission;
const library_1 = require("@prisma/client/runtime/library");
const prisma_1 = require("../prisma");
const matchingEvents = [];
const listeners = new Set();
let nextEventId = 1;
function isZeroLike(value) {
    if (value === null || value === undefined)
        return false;
    try {
        return new library_1.Decimal(String(value)).eq(0);
    }
    catch {
        return false;
    }
}
function normalizeFillPayload(fill) {
    if (fill?.trade) {
        return {
            tradeId: String(fill.trade.id),
            qty: String(fill.trade.qty),
            price: String(fill.trade.price),
            buyOrderId: fill.trade.buyOrderId != null ? String(fill.trade.buyOrderId) : undefined,
            sellOrderId: fill.trade.sellOrderId != null ? String(fill.trade.sellOrderId) : undefined,
        };
    }
    return {
        makerOrderId: fill?.makerOrderId != null ? String(fill.makerOrderId) : undefined,
        takerOrderId: fill?.takerOrderId != null ? String(fill.takerOrderId) : undefined,
        qty: fill?.qty != null ? String(fill.qty) : undefined,
        price: fill?.price != null ? String(fill.price) : undefined,
    };
}
function toEnvelope(record) {
    return {
        id: Number(record.eventId),
        type: record.type,
        ts: record.ts instanceof Date ? record.ts.toISOString() : String(record.ts),
        symbol: String(record.symbol),
        mode: String(record.mode),
        engine: String(record.engine),
        source: record.source,
        payload: (record.payload ?? {}),
    };
}
function emitMatchingEvent(event) {
    const envelope = {
        ...event,
        id: nextEventId++,
    };
    matchingEvents.push(envelope);
    for (const listener of listeners) {
        try {
            listener(envelope);
        }
        catch {
            // listener failures must not break event publication
        }
    }
    return envelope;
}
function emitMatchingEvents(events) {
    return events.map((event) => emitMatchingEvent(event));
}
async function persistMatchingEventEnvelope(envelope, db = prisma_1.prisma) {
    const record = await db.matchingEvent.upsert({
        where: { eventId: envelope.id },
        update: {
            type: envelope.type,
            ts: new Date(envelope.ts),
            symbol: envelope.symbol,
            mode: envelope.mode,
            engine: envelope.engine,
            source: envelope.source,
            payload: envelope.payload,
        },
        create: {
            eventId: envelope.id,
            type: envelope.type,
            ts: new Date(envelope.ts),
            symbol: envelope.symbol,
            mode: envelope.mode,
            engine: envelope.engine,
            source: envelope.source,
            payload: envelope.payload,
        },
    });
    return toEnvelope(record);
}
async function persistMatchingEventEnvelopes(envelopes, db = prisma_1.prisma) {
    const persisted = [];
    for (const envelope of envelopes) {
        persisted.push(await persistMatchingEventEnvelope(envelope, db));
    }
    return persisted;
}
async function listPersistedMatchingEvents(input = {}, db = prisma_1.prisma) {
    const records = await db.matchingEvent.findMany({
        where: {
            ...(input.afterEventId != null ? { eventId: { gt: input.afterEventId } } : {}),
            ...(input.symbol ? { symbol: input.symbol } : {}),
            ...(input.mode ? { mode: input.mode } : {}),
        },
        orderBy: { eventId: "asc" },
        take: input.limit ?? 100,
    });
    return records.map(toEnvelope);
}
function listMatchingEvents(limit = 100) {
    return matchingEvents.slice(-limit);
}
function getMatchingEventCount() {
    return matchingEvents.length;
}
function subscribeMatchingEvents(listener) {
    listeners.add(listener);
    return () => {
        listeners.delete(listener);
    };
}
function getMatchingEventListenerCount() {
    return listeners.size;
}
function resetMatchingEventsForTests() {
    matchingEvents.length = 0;
    listeners.clear();
    nextEventId = 1;
}
function buildMatchingEventsFromSubmission(input) {
    const ts = new Date().toISOString();
    const order = input.order;
    const execution = input.execution ?? {};
    const events = [
        {
            type: "ORDER_ACCEPTED",
            ts,
            symbol: String(order.symbol),
            mode: String(order.mode),
            engine: input.engine,
            source: input.source,
            payload: {
                orderId: String(order.id),
                side: String(order.side),
                price: String(order.price),
                qty: String(order.qty),
                timeInForce: input.timeInForce,
            },
        },
    ];
    const fills = Array.isArray(execution.fills) ? execution.fills : [];
    for (const fill of fills) {
        events.push({
            type: "ORDER_FILL",
            ts,
            symbol: String(order.symbol),
            mode: String(order.mode),
            engine: input.engine,
            source: input.source,
            payload: normalizeFillPayload(fill),
        });
    }
    if (fills.length > 0) {
        events.push({
            type: isZeroLike(execution.remainingQty) ? "ORDER_FILLED" : "ORDER_PARTIALLY_FILLED",
            ts,
            symbol: String(order.symbol),
            mode: String(order.mode),
            engine: input.engine,
            source: input.source,
            payload: {
                orderId: String(order.id),
                remainingQty: execution.remainingQty != null ? String(execution.remainingQty) : undefined,
                fillCount: fills.length,
            },
        });
    }
    if (execution.restingOrderId) {
        events.push({
            type: "ORDER_RESTED",
            ts,
            symbol: String(order.symbol),
            mode: String(order.mode),
            engine: input.engine,
            source: input.source,
            payload: {
                orderId: String(execution.restingOrderId),
                remainingQty: execution.remainingQty != null ? String(execution.remainingQty) : undefined,
            },
        });
    }
    if (execution.tifAction === "CANCEL_REMAINDER" || String(execution.order?.status ?? order.status) === "CANCELLED") {
        events.push({
            type: "ORDER_CANCELLED",
            ts,
            symbol: String(order.symbol),
            mode: String(order.mode),
            engine: input.engine,
            source: input.source,
            payload: {
                orderId: String(order.id),
                remainingQty: execution.remainingQty != null ? String(execution.remainingQty) : undefined,
                reason: execution.tifAction === "CANCEL_REMAINDER" ? "TIF_CANCEL_REMAINDER" : "CANCELLED",
            },
        });
    }
    if (execution.bookDelta) {
        events.push({
            type: "BOOK_DELTA",
            ts,
            symbol: String(order.symbol),
            mode: String(order.mode),
            engine: input.engine,
            source: input.source,
            payload: execution.bookDelta,
        });
    }
    return events;
}
