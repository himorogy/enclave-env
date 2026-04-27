import { execSync } from "node:child_process";
import { resolveEnvFile } from "../config.js";
import type { EnclaveEnvConfig } from "../types.js";

export function encryptEnv(config: EnclaveEnvConfig, env: string): void {
	if (config.mode !== "single") {
		throw new Error(`Mode "${config.mode}" is not yet supported`);
	}
	const filePath = resolveEnvFile(config, env);
	execSync(`dotenvx encrypt -f "${filePath}"`, { stdio: "inherit" });
}
