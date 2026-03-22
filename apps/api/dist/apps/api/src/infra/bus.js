"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.bus = void 0;
// apps/api/src/infra/bus.ts
const node_events_1 = require("node:events");
exports.bus = new node_events_1.EventEmitter();
exports.bus.setMaxListeners(0);
