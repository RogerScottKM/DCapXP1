"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.inMemoryMatchingEngine = exports.InMemoryMatchingEngine = void 0;
const library_1 = require("@prisma/client/runtime/library");
const execution_1 = require("../ledger/execution");
const order_lifecycle_1 = require("../ledger/order-lifecycle");
const reconciliation_1 = require("../ledger/reconciliation");
const order_state_1 = require("../ledger/order-state");
const in_memory_order_book_1 = require("./in-memory-order-book");
class InMemoryMatchingEngine {
    name = "IN_MEMORY_MATCHER";
    books = new Map();
    getBookKey(symbol, mode) {
        return `${symbol}:${mode}`;
    }
    getBook(symbol, mode) {
        const key = this.getBookKey(symbol, mode);
        let existing = this.books.get(key);
        if (!existing) {
            existing = new in_memory_order_book_1.InMemoryOrderBook();
            this.books.set(key, existing);
        }
        return existing;
    }
    async executeLimitOrder(input, db) {
        const order = await db.order.findUniqueOrThrow({
            where: { id: BigInt(String(input.orderId)) },
        });
        const remainingQty = await (0, execution_1.getOrderRemainingQty)(order, db);
        const book = this.getBook(order.symbol, order.mode);
        const bookExecution = book.matchIncoming({
            orderId: order.id.toString(),
            symbol: order.symbol,
            side: order.side,
            price: new library_1.Decimal(order.price),
            qty: remainingQty,
            timeInForce: order.timeInForce ?? "GTC",
            createdAt: order.createdAt,
        });
        const settlementResults = [];
        for (const fill of bookExecution.fills) {
            const makerOrder = await db.order.findUniqueOrThrow({
                where: { id: BigInt(fill.makerOrderId) },
            });
            const fillQty = new library_1.Decimal(fill.qty);
            const executionPrice = new library_1.Decimal(fill.price);
            const quoteFee = new library_1.Decimal(0);
            const buyOrder = order.side === "BUY" ? order : makerOrder;
            const sellOrder = order.side === "SELL" ? order : makerOrder;
            const trade = await db.trade.create({
                data: {
                    symbol: order.symbol,
                    price: executionPrice,
                    qty: fillQty,
                    mode: order.mode,
                    buyOrderId: buyOrder.id,
                    sellOrderId: sellOrder.id,
                },
            });
            const ledgerSettlement = await (0, order_lifecycle_1.settleMatchedTrade)({
                tradeRef: trade.id.toString(),
                buyOrderId: buyOrder.id,
                sellOrderId: sellOrder.id,
                symbol: order.symbol,
                qty: fillQty,
                price: executionPrice,
                mode: order.mode,
                quoteFee,
            }, db);
            const buyPriceImprovementRelease = await (0, execution_1.releaseBuyPriceImprovement)({
                tradeRef: trade.id.toString(),
                orderId: buyOrder.id,
                userId: buyOrder.userId,
                symbol: order.symbol,
                limitPrice: buyOrder.price,
                executionPrice,
                fillQty,
                mode: order.mode,
            }, db);
            const tradeReconciliation = await (0, reconciliation_1.reconcileTradeSettlement)(trade.id, db);
            await (0, execution_1.syncOrderStatusFromTrades)(buyOrder.id, db);
            await (0, execution_1.syncOrderStatusFromTrades)(sellOrder.id, db);
            settlementResults.push({
                trade,
                ledgerSettlement,
                buyPriceImprovementRelease,
                tradeReconciliation,
            });
        }
        let finalOrder = await db.order.findUniqueOrThrow({
            where: { id: order.id },
        });
        const finalRemaining = await (0, execution_1.getOrderRemainingQty)(finalOrder, db);
        const executedQty = new library_1.Decimal(order.qty).minus(finalRemaining);
        if (bookExecution.tifAction === "CANCEL_REMAINDER" && finalRemaining.greaterThan(0)) {
            await (0, order_lifecycle_1.releaseOrderOnCancel)({
                orderId: finalOrder.id,
                userId: finalOrder.userId,
                symbol: finalOrder.symbol,
                side: finalOrder.side,
                qty: finalRemaining,
                price: finalOrder.price,
                mode: finalOrder.mode,
                reason: "CANCEL",
            }, db);
            const currentDerivedStatus = (0, order_state_1.deriveOrderStatus)(finalOrder.status, finalOrder.qty, executedQty);
            (0, order_state_1.assertValidTransition)(currentDerivedStatus, order_state_1.ORDER_STATUS.CANCELLED);
            finalOrder = await db.order.update({
                where: { id: finalOrder.id },
                data: { status: order_state_1.ORDER_STATUS.CANCELLED },
            });
        }
        const orderReconciliation = settlementResults.length > 0
            ? await (0, execution_1.reconcileOrderExecution)(order.id, db)
            : {
                orderId: order.id.toString(),
                status: finalOrder.status,
                expectedStatus: finalOrder.status,
                tradeCount: 0,
                ledgerTransactionCount: 0,
                executedQty: executedQty.toString(),
                remainingQty: finalRemaining.toString(),
            };
        return {
            execution: {
                order: {
                    id: finalOrder.id,
                    symbol: finalOrder.symbol,
                    side: finalOrder.side,
                    price: finalOrder.price,
                    qty: finalOrder.qty,
                    status: finalOrder.status,
                    mode: finalOrder.mode,
                    createdAt: finalOrder.createdAt,
                    timeInForce: finalOrder.timeInForce ?? "GTC",
                },
                fills: bookExecution.fills,
                remainingQty: finalRemaining.toString(),
                tifAction: bookExecution.tifAction,
                restingOrderId: bookExecution.restingOrderId,
                settlements: settlementResults,
                bookDelta: bookExecution.bookDelta,
            },
            orderReconciliation,
            engine: this.name,
        };
    }
}
exports.InMemoryMatchingEngine = InMemoryMatchingEngine;
exports.inMemoryMatchingEngine = new InMemoryMatchingEngine();
