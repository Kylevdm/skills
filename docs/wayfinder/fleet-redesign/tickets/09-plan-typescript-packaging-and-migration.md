---
title: "Plan TypeScript packaging and migration"
labels:
  - wayfinder:grilling
status: closed
parent: ../../fleet-redesign.md
assignee: "claude"
blocked_by:
  - 01-define-fleet-module-interface.md
  - 02-specify-state-machine-and-recovery-protocol.md
  - 03-specify-durable-schemas-and-filesystem-layout.md
  - 05-specify-the-pi-work-unit-protocol.md
  - 06-specify-git-isolation-assembly-refresh-and-landing.md
  - 08-design-the-cli-and-mcp-adapters.md
---

## Question

What packaging, installation, configuration, and cutover sequence moves Fleet
from the shell script to the TypeScript module while retaining a compatibility
shim and read-only legacy-job support? Decide the build and distribution
mechanics, migration of configuration and records, replacement of
`fleet-update`, mechanics, ADRs, and evals, atomic cutover, rollback, and the
point at which old write paths become unavailable.

## Inherited scope (2026-09-10)

[Design the CLI and MCP adapters](08-design-the-cli-and-mcp-adapters.md)
settles that `fleet mcp install` / `uninstall` register the stdio server in the
Codex and Claude MCP configuration, printing the exact diff before writing and
reversing precisely. It deliberately leaves the mechanics here: which
configuration file and key path each host uses, how `install` detects and
refuses to clobber an existing entry, and what `uninstall` does when the entry
has been hand-edited.

It also settles a clean break from the `fleet.sh` verbs with no alias window,
so the cutover sequence this ticket plans must carry that break explicitly.

## Answer

Fleet leaves this repository. The module becomes a standalone public repo,
`Kylevdm/pi-fleet` — MIT, fresh history, no carry-over from `Kylevdm/skills`
(which is public and stays public, so provenance is a link, not a filter-repo
run). The repo is created **now**, empty but for a README declaring it
design-stage, because the map's own tickets move onto its issue tracker at map
agreement. The content moves later; creating the repo and filling it are two
separate moments and the plan does not conflate them.

What remains in `~/skills` is the Claude Code surface and nothing else:
`fleet/SKILL.md` plus a README pointing at the public repo, and
`fleet-update/SKILL.md`. Module source, the shipped registry,
`references/mechanics.md`, ADRs 0001-0003, and `evals/evals.json` all move —
a public repo without its own decision record cannot take contributions.
`evals/trigger-evals.json` stays, because it tests skill triggering rather than
module behaviour.

### Build and run

No build step and no `dist/`. `bin/fleet` is `#!/usr/bin/env node` with
`--experimental-strip-types`, so the source *is* the shipped code — which
matters precisely because `~/.claude/skills/fleet` is a symlink into the repo
and any compiled artifact could go stale against it. `tsc --noEmit` is a
gate, never an output. Distribution is `git clone` to a fixed path plus
`npm link`; npm publish is deferred, not planned, and buys nothing while there
is one consumer. The shebang resolves Node through `env`, so an nvm version
bump survives.

### MCP registration

Each host owns its own file. Claude Code holds `~/.claude.json` in memory and
rewrites it whole, so an external write is silently clobbered: `fleet mcp
install` shells out to `claude mcp add-json fleet '<json>' --scope user`, and
falls back to printing the snippet for the human if `claude` is not on `PATH`.
Codex reads `~/.codex/config.toml` at startup and never rewrites it, so
`[mcp_servers.fleet]` is edited in place under ticket 03's atomic-rename
discipline. Either way Fleet computes and prints the exact entry first,
honouring ticket 08's diff-before-write requirement.

No ownership marker is written into either config — an extra key in an MCP
entry is not portable and a TOML comment does not survive a rewrite. `install`
refuses with `conflict` if a `fleet` key exists at all, printing both entries;
`--force` replaces. `uninstall` recomputes the entry `install` would write
today and compares: identical removes silently, different prints the diff,
removes nothing, and exits `conflict` unless `--force`. A hand-edited entry is
one Fleet cannot claim.

### No migration, because there is nothing to migrate

New records live in fresh subtrees per ticket 03; the old store is never read
and never written. Pre-cutover job directories are left inert under
`~/.pi/fleet/<repo>/<slug>/` — Fleet ignores them entirely and ships no purge
verb for them, because deleting a user's old work is not a first-run act. The
documented cleanup is a hand-run `rm -rf`. The profile table is re-expressed as
the shipped registry rather than converted. `store.json` is created empty at
`epoch: 1` on first run.

**This amends two closed tickets.** [Specify durable schemas and filesystem
layout](03-specify-durable-schemas-and-filesystem-layout.md) specified legacy
recognition, and [Design the CLI and MCP
adapters](08-design-the-cli-and-mcp-adapters.md) specified `legacy: true`
listing with `policy-denied` elsewhere. Both are struck: legacy support is
removed outright, which deletes a code path rather than adding one, and makes
ticket 03's "never writes outside its four subtrees" literally true.

### `fleet-update` after the split

It survives as a skill and stops being a file editor. It reads `fleet evidence`
and `fleet probe` over MCP and writes exactly one artifact, the local overlay.
The shipped registry lives in `pi-fleet` and only a human PR changes it —
ticket 04's decision honoured across a repo boundary. Its "four files make up
the config surface" table dies with the shell script.

### Cutover

`fleet/scripts/fleet.sh` is **frozen** the moment the plan is agreed: still
runnable, no further edits. Making the freeze explicit is what stops a routing
tweak landing in a file scheduled for deletion. The module is built greenfield
in its own repo; the two are never run side by side, because they share no
records and ticket 05's protocol is already verified live, so a comparison
would prove nothing.

Ordered sequence — **link and register first, delete second**:

1. Create `Kylevdm/pi-fleet` (public, MIT, empty). Freeze `fleet.sh`.
2. Move the module-facing content in; build the module against it.
3. Clone to a fixed path, `npm link`, `fleet mcp install`, verify on both hosts.
4. Tag the pre-cutover commit in `~/skills` as `pre-fleet-ts`.
5. **One commit** in `~/skills`: delete `fleet/scripts/fleet.sh`, replace
   `fleet/SKILL.md`, rewrite `fleet-update/SKILL.md`, move `mechanics.md`,
   the ADRs and `evals.json` out, leave `trigger-evals.json`.

Old write paths become unavailable at step 5 and not before. Because the skill
directory is a symlink, that deletion is live the instant the commit lands —
there is no install step to sequence around, and no alias window, as ticket 08
requires. Rollback is `git revert` of that one commit (or reset to
`pre-fleet-ts`), `npm unlink`, `fleet mcp uninstall`. There is no data state to
reverse at any point, which is the whole payoff of keeping the two stores
disjoint.

The module is tested incrementally as it is built rather than only at the end.
What must pass, and when, is [Define verification and rollout
gates](10-define-verification-and-rollout-gates.md)'s to settle.
