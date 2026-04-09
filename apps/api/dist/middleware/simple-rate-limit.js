"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.simpleRateLimit = simpleRateLimit;
const buckets = new Map();
function getClientIp(req) {
    const forwarded = req.headers["x-forwarded-for"];
    if (typeof forwarded === "string" && forwarded.trim()) {
        return forwarded.split(",")[0].trim();
    }
    return req.socket.remoteAddress ?? "unknown";
}
function simpleRateLimit(options) {
    return (req, res, next) => {
        const now = Date.now();
        const key = `${options.keyPrefix}:${getClientIp(req)}`;
        const current = buckets.get(key);
        const bucket = !current || current.resetAt <= now
            ? { count: 0, resetAt: now + options.windowMs }
            : current;
        bucket.count += 1;
        buckets.set(key, bucket);
        res.setHeader("X-RateLimit-Limit", String(options.max));
        res.setHeader("X-RateLimit-Remaining", String(Math.max(0, options.max - bucket.count)));
        res.setHeader("X-RateLimit-Reset", String(Math.ceil(bucket.resetAt / 1000)));
        if (bucket.count > options.max) {
            return res.status(429).json({
                error: {
                    code: "RATE_LIMITED",
                    message: "Too many requests. Please try again later.",
                },
            });
        }
        return next();
    };
}
