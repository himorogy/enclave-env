import { execSync } from "node:child_process";
import { resolveEnvFile } from "../config.js";
import { checkDevContainerNotRunning } from "../security.js";
import type { EnclaveEnvConfig } from "../types.js";

export function decryptEnv(config: EnclaveEnvConfig, env: string): void {
	if (config.mode !== "single") {
		throw new Error(`Mode "${config.mode}" is not yet supported`);
	}
	const envConfig = config.environments[env];
	if (envConfig?.protected && config.security?.devContainerName) {
		checkDevContainerNotRunning(config.security.devContainerName);
	}
	const filePath = resolveEnvFile(config, env);
	execSync(`dotenvx decrypt -f "${filePath}"`, { stdio: "inherit" });
}
