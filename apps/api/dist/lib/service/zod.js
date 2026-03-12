"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseDto = parseDto;
function parseDto(schema, input) {
    return schema.parse(input);
}
