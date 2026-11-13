/**
 * Command gate
 *
 * Blocks bash commands that publish, reach the network directly, change the
 * environment, or touch real Home Assistant. Non-interactive runs (delegation)
 * block outright; interactive sessions ask first.
 *
 * Pattern matching is a guard rail, not a boundary: the pi-jail wrapper is what
 * keeps credentials (HA token, SSH keys, gh auth) out of reach.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const DANGEROUS: [RegExp, string][] = [
	[/\bgit\s+(push|commit|tag|merge|rebase|reset\s+--hard|config)\b/, "git write/publish"],
	[/\bgh\b/, "GitHub CLI"],
	[/\b(curl|wget|nc|ncat|ssh|scp|rsync)\b/, "direct network access"],
	[/\b(pip|pip3|uv|npm|pnpm|yarn)\s+(install|add|uninstall|remove)\b/, "dependency change"],
	[/\bpython3?\s+-m\s+ha_spark\b/, "ha-spark CLI (talks to real HA)"],
	[/\bsudo\b/, "sudo"],
	[/\brm\s+-[a-z]*r[a-z]*f?\s+(\/|~|\$HOME)/i, "recursive delete outside worktree"],
	[/\b(chmod|chown)\b.*\b777\b/, "world-writable permissions"],
];

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;
		const command = String(event.input.command ?? "");
		const hit = DANGEROUS.find(([p]) => p.test(command));
		if (!hit) return undefined;

		const reason = `Blocked (${hit[1]}): leave this step to the orchestrator`;
		if (!ctx.hasUI) return { block: true, reason };

		const choice = await ctx.ui.select(`⚠️ ${hit[1]}:\n\n  ${command}\n\nAllow?`, ["No", "Yes"]);
		return choice === "Yes" ? undefined : { block: true, reason: "Blocked by user" };
	});
}
