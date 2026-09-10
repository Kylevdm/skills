---
title: "Design the CLI and MCP adapters"
labels:
  - wayfinder:prototype
status: closed
parent: ../../fleet-redesign.md
assignee: "claude"
blocked_by:
  - 01-define-fleet-module-interface.md
  - 02-specify-state-machine-and-recovery-protocol.md
  - 03-specify-durable-schemas-and-filesystem-layout.md
---

## Question

How do the compatibility JSON CLI and local stdio MCP server expose the Fleet
module without duplicating its policy? Decide typed requests and bounded,
credential-redacted responses; polling and durable admission; diff and check
evidence bounds; repository-root allowlisting; mutation auditing; confirmation
for destructive operations; explicit reversible Codex and Claude registration;
and compatibility behavior for legacy shell jobs.

## Answer

Fleet has one application layer and two thin translators. Neither adapter holds
a state transition, a retry, a routing choice, or an evidence bound; each maps
one caller request onto one `Fleet` method and renders what comes back.

### One envelope

Every tool result and every `--json` CLI result is the same object, so a caller
learns one shape:

```jsonc
{
  "ok": true,
  "jobId": "01JQ...",        // opaque, ULID
  "revision": 7,             // feed back as expectedRevision
  "status": "running",       // the seven public states only
  "stage": "writing",        // current internal stage, display-only
  "next": ["fleet_wait", "fleet_get", "fleet_cancel"],
  "evidence": { "diff": "art:01JQ.../03/diff" }
}
```

A failure is `{ "ok": false, "problem": ..., "revision": ..., "message": ... }`
where `problem` is exactly ticket 01's taxonomy — `invalid-input`,
`policy-denied`, `conflict`, `not-found`, `stale-confirmation`,
`unavailable-dependency`, `capacity` — and nothing else ever appears.

`next` is what keeps policy out of the adapters and out of the primary's head:
Fleet already knows which transitions are legal, so the caller never reasons
about the state machine to find its next move.

### Hand-back is a bounded long-poll

The adapters add one operation to the module, `wait`, exposed as `fleet_wait`
and `fleet wait`. It blocks server-side until the job reaches a state the
primary can act on, then returns the standard envelope.

- `timeoutSeconds` is **clamped to 60**, below every known MCP host timeout, and
  a timed-out wait returns a normal `ok` envelope with `timedOut: true`. A
  transport error therefore never masquerades as a finished job, and there is no
  polling fallback to maintain.
- It wakes only on **actionable** states: `ready-for-acceptance`,
  `returned-to-orchestrator`, `cancelled`. Internal stage churn and `waiting`
  pauses on capacity or provider recovery do not wake it.
- The server observes `job.json`'s revision through the store adapter. Whether
  that is a filesystem watch or an interval is an implementation detail bounded
  by one second of detection latency.

**Stated consequence.** A 60-second ceiling with actionable-only wakes does not
reduce the *number* of primary turns below a 60-second poll — a 40-minute job
still returns `timedOut` about forty times if the primary re-arms immediately.
What it buys is latency and precision: a real hand-back returns within a second
instead of waiting out a poll interval, and no turn is ever spent on a
transition the primary cannot act on. The primary is free to re-arm on its own
cadence, and doing so lazily is exactly ordinary polling with a better wake
signal. If turn count later proves to be the binding cost rather than latency,
the ceiling is the single number to revisit.

### Confirmation

`purge` keeps ticket 03's two-call preview-token protocol, and it is the only
operation that confirms inside Fleet. `cancel`, `clean`, and `land` are
ordinary mutations guarded by `expectedRevision`; the MCP host's own approval
prompt is the human gate. Fleet does not reimplement an approval surface it
cannot see, and does not double-charge the common path a turn to do it.

### The surfaces

Sixteen verbs: ticket 01's thirteen, ticket 04's `evidence` and `probe`, and
`wait`. Both adapters carry all sixteen. `evidence` and `probe` are read-only
maintenance calls that `fleet-update` consumes; exposing them over MCP is what
lets `fleet-update` run as a skill inside a primary session.

The MCP server is local stdio, one process per user, started by the host. There
is no generic `fleet_exec` and no arbitrary command string. It resolves every
repository path to a realpath, requires it on an explicit allowlist, validates
job ids against the ULID pattern, never accepts a caller-supplied state path or
provider credential, redacts known credential shapes before any content leaves
the module, and writes an `audit.jsonl` entry for every mutating call including
rejected ones.

The CLI is `fleet <verb>`, with `--json` printing exactly one envelope object on
stdout and nothing else. Exit status is `0` for `ok`, `1` for a typed `problem`,
`2` for an unexpected fault.

### Registration

`fleet mcp install` and `fleet mcp uninstall` write and remove the server entry
in the Codex and Claude MCP configuration. `install` prints the exact diff
before writing and `uninstall` is its precise inverse, satisfying the ticket's
"explicit reversible" requirement. The concrete file paths, key paths, and
existing-entry detection are installation mechanics: **[Plan TypeScript
packaging and migration](09-plan-typescript-packaging-and-migration.md)
inherits them** rather than a new ticket.

### Compatibility is a clean break

The old `fleet.sh` verbs — `launch`, `status`, `log`, `resume`, `verify`,
`_finish` — are gone. An old invocation fails with a pointer to the new verb;
there are no permanent aliases and no deprecation window.

Legacy shell jobs remain readable, because ticket 03 already keeps their
directories untouched. A directory holding `meta.json` with no sibling
`job.json` lists with `legacy: true` and accepts only `get`, `diff`, and
`clean`. Every other verb on a legacy job returns `policy-denied`. Fleet never
migrates one into the new store.

Prototype: `../assets/08-cli-mcp-adapters/surface.md`.

## Amendment (2026-09-10)

[Plan TypeScript packaging and migration](09-plan-typescript-packaging-and-migration.md)
strikes legacy shell-job support. There is no `legacy: true` listing and no
`policy-denied` legacy branch: pre-cutover directories are invisible to Fleet.
The clean break from `fleet.sh` stands and is now total — the script is deleted
rather than kept readable, and its verbs get no pointer stub.

It also settles the registration mechanics this ticket deferred: Claude via
`claude mcp add-json --scope user` (never a direct `~/.claude.json` write),
Codex via an in-place `[mcp_servers.fleet]` TOML edit, no ownership marker in
either, `conflict` on an existing or hand-edited entry unless `--force`.

## Amendment (2026-09-10, ticket 10)

[Define verification and rollout
gates](10-define-verification-and-rollout-gates.md) adds two fields to the
envelope: `warnings: []`, a **closed enum** held to the same discipline as the
`problem` taxonomy above — `risk-raised-by-agent`, `escalation-consumed`,
`reviewer-family-constraint-dropped`, `integration-rung-used`,
`command-blocked`, `availability-rotation`, `refresh-rebased`,
`model-overridden` — and `reviewDepth: "normal" | "elevated"`, derived from the
first five. Elevated means the primary reads the diff itself rather than
accepting on summary plus green checks. Adding a code is an interface
amendment, never a free-form addition.
