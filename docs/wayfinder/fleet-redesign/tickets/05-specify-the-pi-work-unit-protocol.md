---
title: "Specify the Pi work-unit protocol"
labels:
  - wayfinder:prototype
status: closed
parent: ../../fleet-redesign.md
assignee: "claude"
blocked_by:
  - 02-specify-state-machine-and-recovery-protocol.md
  - 03-specify-durable-schemas-and-filesystem-layout.md
  - 04-specify-routing-and-evaluation-mechanics.md
---

## Question

How does Fleet drive Pi through JSONL RPC or the Pi SDK for scouting,
planning, writing, and review? Decide lifecycle commands, role briefs, tool
and command policy, structured output schemas, timeout and termination
handling, session and usage capture, infrastructure versus quality failure
classification, reviewer-family selection, and whether Pi's controls can
enforce the required accepted-command policy without a custom extension.

## Resolution

Fleet drives Pi as a **detached `pi --mode rpc` subprocess per stage**, gated and shaped by one
Fleet-shipped extension, and seals each stage on a terminating `submit_*` tool call. Verified
live against Pi 0.85.1 and `opencode-go/minimax-m3` — see
[the spike](../assets/05-pi-work-unit-spike/), which ran the full loop end to end: RPC prompt,
allowlist block, structured seal, real usage capture, committed change.

`fleet/references/mechanics.md` is materially out of date on Pi's control surface. It states Pi
has no way to constrain a delegated agent and documents only `-p`. Pi 0.85.1 has `--mode
rpc`/`--mode json`, `--tools`/`--exclude-tools`/`--no-builtin-tools`, and a blocking `tool_call`
extension hook. Correcting that file is implementation work, noted here so it is not lost.

### Transport

One detached `pi --mode rpc` child process per stage, never `createAgentSession()` in the
supervisor's own process. Ticket 02 requires recovery to reconcile an in-flight call and, where
the process is still live, resume watching it. In-process SDK calls die with the supervisor, so
that branch would collapse to `returned-to-orchestrator` on every supervisor crash — the exact
primary-orchestrator token cost Fleet exists to avoid. A subprocess also gives the call intent a
real pid to record and cancellation a real target to confirm terminated.

`--mode json` is rejected as the primary transport: it has no stdin channel, so there is no
`abort` command, and cancellation degrades to SIGTERM. Ticket 02's requirement to seal all
recoverable evidence on cancellation needs the graceful rung.

RPC framing is strict JSONL on LF only. Pi's docs call out that Node `readline` is **not**
protocol-compliant, because it also splits on U+2028/U+2029, which are legal inside JSON strings.
Fleet's reader splits on `\n`, strips a trailing `\r`, and never uses `readline`.

### Stage sessions

Each of `scouting`, `planning`, `writing`, and `reviewing` is its own Pi process with its own
`--session-id`, its own model selection from ticket 04's registry, and its own tool set. A single
long-lived session per job was rejected: ticket 02 seals an immutable stage artifact and never
re-runs a sealed stage, and a sealed artifact is a fiction while the context carrying it stays
mutable. Stage handoff is by artifact, not by shared session.

Brief assembly is therefore owned by this protocol. A stage brief is the role brief, plus the
job's immutable input snapshot, plus the verbatim sealed artifacts of the stages this one
depends on. Nothing else crosses a stage boundary.

Scouting exists only on the `discovery` path. The `direct` path runs `preparing` → `writing`,
holding the line ticket 02 already drew: a direct job arrives with a ticket whose author already
did the scouting, and re-scouting spends a stage on work the primary orchestrator has done.

### The Fleet extension

Fleet ships **one** extension, loaded with `-e`, carrying three responsibilities that share the
run's job context:

1. A per-role terminating `submit_*` tool with a TypeBox parameter schema. `terminate: true` ends
   the run on the tool call with no extra LLM turn — confirmed in the spike, where the writer's
   eight assistant messages were all `stopReason: "toolUse"` and no trailing assistant turn was
   billed.
2. The `tool_call` command gate (below).
3. A `raise_risk` tool, since ticket 04 lets a delegated agent raise the risk class and never
   lower it.

A stage seals **only** on a `submit_*` tool result. Prose in the final assistant message is
retained as transcript but is never the artifact. This is what makes ticket 02's "invalid or
irrelevant output" a crisp mechanical test rather than a parsing judgement call: either the
schema-validated tool result exists or the stage produced nothing.

Per-role schemas are minimal and shared-shaped: every `submit_*` carries `summary`,
`contractMet`, and the role's own payload — `filesTouched` and `commandsRun` for the writer,
`verdict` and `findings` for the reviewer, the ordered stage plan for the planner.

### Tool and command policy

Tool exposure is by `--tools` allowlist, not by instruction:

- Scout and reviewer: `read,grep,find,ls` plus the role's `submit_*`. Read-only is enforced by
  the absence of `bash`, `edit`, and `write`.
- Writer: `read,bash,edit,write,grep,find,ls`, plus `submit_write` and `raise_risk`.

The reviewer runs in its **own read-only second worktree** checked out at the writer's sealed
commit. It cannot mutate what it is judging, and it is guaranteed to judge the sealed commit
rather than a tree the writer may still be touching. Ticket 06 owns provisioning that worktree.

Command content is gated by the extension's `tool_call` handler, which returns
`{block: true, reason}` for any bash call whose resolved argv head is not on the
accepted-command allowlist. Fleet ships a conservative default list — `git`, `node`, `npm`,
`pnpm`, `python3`, `make`, `rg`, and the common test runners — extended per repository through
the same `config.json` overlay pattern ticket 04 settled for the model registry, so a fresh
install delegates correctly with no setup. An unconditional deny covers `sudo`, network fetches,
and any path under `~/.pi/agent/`. Three blocks in one stage is a quality failure.

**Pi's built-in controls cannot enforce this policy alone**, which answers the ticket's last
clause directly. `--tools` is coarse — bash is on or off — and Pi has no command-level control
and, by explicit design (`docs/security.md`), no sandbox at all. A custom extension is required.
It is small, and Pi ships two working precedents in `examples/extensions/`
(`permission-gate.ts`, `protected-paths.ts`). The spike's gate is 12 lines.

The block is **legible to the model, not fatal to the run**: the spike's writer hit the blocked
`curl`, routed around it, completed the real work, and reported the block honestly in its
`commandsRun`. A silent block would have invited a fabricated result.

### Failure classification

Classified at the event stream, with `agent_start` as the whole discriminator — before it,
nothing was spent on the work; after it, the model had its chance.

Infrastructure (ticket 02: no quality attempt spent, rotate to another model):

- process exits non-zero before any `agent_start`
- no `agent_start` within the launch timeout
- first assistant message carries `stopReason: "error"` with a provider auth, credit, region, or
  endpoint error

Quality (seals evidence, consumes the attempt):

- `agent_settled` reached with no `submit_*` tool result
- `stopReason: "length"` — context exhausted mid-work
- a `submit_*` result that fails its own contract, or failing checks or reviewer verdict
- timeout after `agent_start` was observed

`agent_settled`, not `agent_end`, is the end-of-run signal. `agent_end` can be followed by
automatic retry or compaction retry, so sealing on it would seal a run Pi has not finished.

### Session and usage capture

Per-assistant-message `usage` carries `input`, `output`, `cacheRead`, `cacheWrite`,
`totalTokens`, and a provider-computed `cost` breakdown, alongside `provider`, `model`, and
`stopReason`. Ticket 04's attempt record fills straight from the event stream — no estimation,
no separate accounting call.

**Usage must be summed across every assistant message in the stage, never read from the final
one.** In the spike the last message reported 5,970 tokens and $0.00092 while the stage's true
totals were 41,503 tokens and $0.00597 — a 6.5x under-count. The `message_update` top-level
`usage` field is a cumulative *provider* snapshot and may stay zero with providers that only
report at completion, so it is not a substitute.

Fleet retains **Pi's own session file**, addressed by `--session-dir` plus `--session-id`, as the
durable transcript, and does not persist the raw RPC event stream. The spike's session file was
17KB against 160KB of raw events for the same trivial change: the event stream is roughly ten
times larger because of delta streaming, and carries nothing the session file lacks. The event
stream is consumed live for classification and usage, then discarded.

### Timeouts and termination

Two timeouts, both recorded in the call intent: a **launch timeout** (default 90s, to first
`agent_start`) and the **stage deadline** from the stage plan. Termination escalates `abort` over
stdin, then SIGTERM at +10s, then SIGKILL at +30s, recording which rung was reached. Ticket 02's
"cannot confirm termination before the cancellation deadline" path is precisely the SIGKILL rung
failing.

Note for implementation: a driver that SIGTERMs its own child after `agent_settled` sees exit
143, not 0. Exit code alone is not an outcome signal — the sealed artifact is.

## Amendment (2026-09-10)

[Specify check-command discovery and the checking stage
contract](16-specify-check-command-discovery.md) makes one narrow exception to
"nothing else crosses a stage boundary": the resolved check command list joins
the stage brief as job-level context. A writer judged against a command it was
never shown produces manufactured quality failures, and the disclosure is what
makes the writer's `commandsRun` self-report comparable to Fleet's independent
run.

`checking` is confirmed as a stage that spawns **no** Pi process — Fleet runs
the configured commands as its own children and seals their exit codes.
