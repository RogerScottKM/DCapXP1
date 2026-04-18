import * as dotenv from "dotenv";
import { spawn, type SpawnOptions } from "node:child_process";

import { bootstrapSecrets } from "../lib/bootstrap-secrets";
import { loadVaultBootstrapEnv } from "./vault-bootstrap-env";

dotenv.config();

export async function runVaultExec(
  argv: string[] = process.argv.slice(2),
  spawnImpl: typeof spawn = spawn,
  env: NodeJS.ProcessEnv = process.env,
): Promise<void> {
  const [command, ...args] = argv;
  if (!command) {
    throw new Error("No command provided to vault-exec");
  }

  loadVaultBootstrapEnv(process.cwd(), __dirname);
  await bootstrapSecrets();

  await new Promise<void>((resolve, reject) => {
    const options: SpawnOptions = {
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

async function main(): Promise<void> {
  try {
    await runVaultExec();
  } catch (error) {
    console.error("[vault-exec] failed", error);
    process.exit(1);
  }
}

if (require.main === module) {
  void main();
}
