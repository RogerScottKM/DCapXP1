"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateUIPlan = generateUIPlan;
const ui_1 = require("@repo/schema/ui");
const persona_1 = require("./persona");
const widgets_1 = require("./widgets");
function generateUIPlan(input) {
    const req = ui_1.UIPlanRequestSchema.parse(input);
    const persona = (0, persona_1.inferPersona)(req.userId);
    const intent = req.intent;
    const symbol = req.symbol;
    const ctx = { req, persona, intent, symbol };
    const layout = widgets_1.widgetCandidates
        .filter((c) => (c.when ? c.when(ctx) : true))
        .sort((a, b) => a.priority - b.priority)
        .map((c) => ({
        id: c.id,
        priority: c.priority,
        colSpan: c.colSpan,
        widget: c.build(ctx),
    }));
    return ui_1.UIPlanSchema.parse({
        version: "1.0",
        generatedFor: { userId: req.userId, persona, intent, symbol },
        layout,
    });
}
