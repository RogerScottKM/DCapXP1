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
Object.defineProperty(exports, "__esModule", { value: true });
exports.runVaultExec = runVaultExec;
const dotenv = __importStar(require("dotenv"));
const node_child_process_1 = require("node:child_process");
const bootstrap_secrets_1 = require("../lib/bootstrap-secrets");
const vault_bootstrap_env_1 = require("./vault-bootstrap-env");
dotenv.config();
async function runVaultExec(argv = process.argv.slice(2), spawnImpl = node_child_process_1.spawn, env = process.env) {
    const [command, ...args] = argv;
    if (!command) {
        throw new Error("No command provided to vault-exec");
    }
    (0, vault_bootstrap_env_1.loadVaultBootstrapEnv)(process.cwd(), __dirname);
    await (0, bootstrap_secrets_1.bootstrapSecrets)();
    await new Promise((resolve, reject) => {
        const options = {
            stdio: "inherit",
            env,
            shell: false,
        };
        const child = spawnImpl(command, args, options);
        child.once("error", (error) => {
            reject(error);
        });
        child.once("exit", (code) => {
            if (code === 0) {
                resolve();
                return;
            }
            reject(new Error(`vault-exec child exited with code ${String(code)}`));
        });
    });
}
async function main() {
    try {
        await runVaultExec();
    }
    catch (error) {
        console.error("[vault-exec] failed", error);
        process.exit(1);
    }
}
if (require.main === module) {
    void main();
}
