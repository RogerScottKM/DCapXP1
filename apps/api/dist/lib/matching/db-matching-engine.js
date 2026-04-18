"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.dbMatchingEngine = exports.DbMatchingEngine = void 0;
const ledger_1 = require("../ledger");
class DbMatchingEngine {
    name = "DB_MATCHER";
    async executeLimitOrder(input, db) {
        const execution = await (0, ledger_1.executeLimitOrderAgainstBook)({
            orderId: input.orderId,
            quoteFeeBps: input.quoteFeeBps ?? "0",
        }, db);
        const orderReconciliation = await (0, ledger_1.reconcileOrderExecution)(input.orderId, db);
        return {
            execution,
            orderReconciliation,
            engine: this.name,
        };
    }
}
exports.DbMatchingEngine = DbMatchingEngine;
exports.dbMatchingEngine = new DbMatchingEngine();
