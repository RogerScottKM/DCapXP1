"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.selectMatchingEngine = selectMatchingEngine;
const db_matching_engine_1 = require("./db-matching-engine");
const in_memory_matching_engine_1 = require("./in-memory-matching-engine");
function selectMatchingEngine(preferred) {
    const selected = String(preferred ?? process.env.MATCHING_ENGINE ?? "db").trim();
    if (selected === "in_memory" || selected === "IN_MEMORY_MATCHER") {
        return in_memory_matching_engine_1.inMemoryMatchingEngine;
    }
    return db_matching_engine_1.dbMatchingEngine;
}
