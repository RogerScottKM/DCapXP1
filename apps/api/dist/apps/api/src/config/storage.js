"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.storageConfig = void 0;
exports.storageConfig = { bucketName: process.env.STORAGE_BUCKET_NAME, region: process.env.STORAGE_REGION, endpoint: process.env.STORAGE_ENDPOINT || undefined };
