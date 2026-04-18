"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.findRepoRoot = findRepoRoot;
exports.resolveVaultBootstrapFile = resolveVaultBootstrapFile;
exports.loadVaultBootstrapEnv = loadVaultBootstrapEnv;
const node_fs_1 = __importDefault(require("node:fs"));
const node_path_1 = __importDefault(require("node:path"));
const dotenv = __importStar(require("dotenv"));
const HOST_BOOTSTRAP_FILENAME = ".env.vault.host";
function fileExists(filePath) {
    try {
        return node_fs_1.default.existsSync(filePath);
    }
    catch {
        return false;
    }
}
function findRepoRoot(startDir) {
    let current = node_path_1.default.resolve(startDir);
    while (true) {
        const markers = [
            node_path_1.default.join(current, "pnpm-workspace.yaml"),
            node_path_1.default.join(current, "docker-compose.yml"),
            node_path_1.default.join(current, ".git"),
        ];
        if (markers.some(fileExists)) {
            return current;
        }
        const parent = node_path_1.default.dirname(current);
        if (parent === current) {
            return null;
        }
        current = parent;
    }
}
function resolveVaultBootstrapFile(cwd = process.cwd(), scriptDir = __dirname, explicitPath) {
    const envOverride = explicitPath ?? process.env.VAULT_BOOTSTRAP_FILE ?? null;
    if (envOverride) {
        const resolved = node_path_1.default.resolve(envOverride);
        return fileExists(resolved) ? resolved : null;
    }
    const candidates = new Set();
    candidates.add(node_path_1.default.resolve(cwd, HOST_BOOTSTRAP_FILENAME));
    const cwdRoot = findRepoRoot(cwd);
    if (cwdRoot) {
        candidates.add(node_path_1.default.join(cwdRoot, HOST_BOOTSTRAP_FILENAME));
    }
    const scriptRoot = findRepoRoot(scriptDir);
    if (scriptRoot) {
        candidates.add(node_path_1.default.join(scriptRoot, HOST_BOOTSTRAP_FILENAME));
    }
    for (const candidate of candidates) {
        if (fileExists(candidate)) {
            return candidate;
        }
    }
    return null;
}
function loadVaultBootstrapEnv(cwd = process.cwd(), scriptDir = __dirname) {
    const resolved = resolveVaultBootstrapFile(cwd, scriptDir);
    if (!resolved) {
        return null;
    }
    dotenv.config({
        path: resolved,
        override: true,
    });
    return resolved;
}
