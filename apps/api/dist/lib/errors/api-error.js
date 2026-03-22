"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ApiError = void 0;
class ApiError extends Error {
    statusCode;
    code;
    fieldErrors;
    retryable;
    constructor(args) { super(args.message); this.statusCode = args.statusCode; this.code = args.code; this.fieldErrors = args.fieldErrors; this.retryable = args.retryable; }
}
exports.ApiError = ApiError;
