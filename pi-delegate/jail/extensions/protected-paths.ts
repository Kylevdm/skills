/**
 * Protected paths
 *
 * Blocks write/edit outside the working directory, on .env* (except *.example)
 * and git internals, and on the repo's own list in
 * ~/.config/pi-jail/protect/<repo-name> (one path per line, relative to the
 * repo root; a trailing "/" protects a directory).
 *
 * This is a guard rail, not a boundary: bash can still write files. pi-jail
 * enforces the same list with read-only bind mounts.
 */

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const ALWAYS: RegExp[] = [/(^|\/)\.env$/, /(^|\/)\.env\.(?!example$)/, /(^|\/)\.git(\/|$)/];

async function repoList(pi: ExtensionAPI): Promise<string[]> {
	const { stdout, code } = await pi.exec("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
	if (code !== 0) return [];
	const file = join(homedir(), ".config", "pi-jail", "protect", basename(dirname(stdout.trim())));
	if (!existsSync(file)) return [];
	return readFileSync(file, "utf8")
		.split("\n")
		.map((l) => l.replace(/#.*/, "").trim())
		.filter(Boolean);
}

export default function (pi: ExtensionAPI) {
	let listed: Promise<string[]> | undefined;

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "write" && event.toolName !== "edit") return undefined;
		listed ??= repoList(pi);
		const list = await listed;

		const raw = String(event.input.path ?? "");
		const rel = relative(ctx.cwd, isAbsolute(raw) ? raw : resolve(ctx.cwd, raw));
		const outside = rel.startsWith("..") || isAbsolute(rel);
		const hit =
			ALWAYS.some((p) => p.test(rel)) ||
			list.some((p) => (p.endsWith("/") ? rel.startsWith(p) : rel === p));

		if (!outside && !hit) return undefined;
		const reason = outside
			? `"${raw}" is outside the working directory`
			: `"${rel}" is protected; report the change you need instead of making it`;
		if (ctx.hasUI) ctx.ui.notify(`Blocked: ${reason}`, "warning");
		return { block: true, reason };
	});
}
