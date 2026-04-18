"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.submitLimitOrder = submitLimitOrder;
const client_1 = require("@prisma/client");
const prisma_1 = require("../prisma");
const ledger_1 = require("../ledger");
const time_in_force_1 = require("../ledger/time-in-force");
const order_state_1 = require("../ledger/order-state");
const select_engine_1 = require("./select-engine");
const serialized_dispatch_1 = require("./serialized-dispatch");
const matching_events_1 = require("./matching-events");
const admission_controls_1 = require("./admission-controls");
async function submitLimitOrder(input, db = prisma_1.prisma, engine) {
    const normalizedTimeInForce = (0, time_in_force_1.normalizeTimeInForce)(input.timeInForce);
    const selectedEngine = engine ?? (0, select_engine_1.selectMatchingEngine)(input.preferredEngine);
    return db.$transaction(async (tx) => {
        await (0, admission_controls_1.enforceAdmissionControls)({
            db: tx,
            userId: input.userId,
            symbol: input.symbol,
            mode: String(input.mode),
            price: input.price,
        });
        const order = await tx.order.create({
            data: {
                symbol: input.symbol,
                side: input.side,
                price: new client_1.Prisma.Decimal(input.price),
                qty: new client_1.Prisma.Decimal(input.qty),
                status: order_state_1.ORDER_STATUS.OPEN,
                timeInForce: normalizedTimeInForce,
                mode: input.mode,
                userId: input.userId,
            },
        });
        const ledgerReservation = await (0, ledger_1.reserveOrderOnPlacement)({
            orderId: order.id,
            userId: input.userId,
            symbol: input.symbol,
            side: input.side,
            qty: input.qty,
            price: input.price,
            mode: input.mode,
        }, tx);
        const executeThroughSelectedEngine = () => selectedEngine.executeLimitOrder({
            orderId: order.id,
            quoteFeeBps: input.quoteFeeBps ?? "0",
        }, tx);
        const engineResult = selectedEngine.name === "IN_MEMORY_MATCHER"
            ? await (0, serialized_dispatch_1.runSerializedByKey)((0, serialized_dispatch_1.buildSymbolModeKey)(input.symbol, String(input.mode)), executeThroughSelectedEngine)
            : await executeThroughSelectedEngine();
        const events = (0, matching_events_1.buildMatchingEventsFromSubmission)({
            order,
            execution: engineResult.execution,
            engine: engineResult.engine,
            source: input.source,
            timeInForce: normalizedTimeInForce,
        });
        const emittedEvents = (0, matching_events_1.emitMatchingEvents)(events);
        await (0, matching_events_1.persistMatchingEventEnvelopes)(emittedEvents, tx);
        return {
            order,
            ledgerReservation,
            execution: engineResult.execution,
            orderReconciliation: engineResult.orderReconciliation,
            engine: engineResult.engine,
            source: input.source,
            timeInForce: normalizedTimeInForce,
            events: emittedEvents,
        };
    });
}
