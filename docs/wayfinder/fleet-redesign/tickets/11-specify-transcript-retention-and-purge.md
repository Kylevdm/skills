---
title: "Specify transcript retention and purge"
labels:
  - wayfinder:grilling
status: closed
parent: ../../fleet-redesign.md
assignee: "claude"
blocked_by:
  - 03-specify-durable-schemas-and-filesystem-layout.md
  - 05-specify-the-pi-work-unit-protocol.md
---

## Question

What retention, size cap, rotation, and purge policy applies to the Pi session
files Fleet keeps as each stage's durable transcript? Decide the per-job and
per-store ceilings, what happens when a job's transcripts exceed them mid-run,
whether an archived job's transcripts are retained at full fidelity or reduced,
how redaction interacts with rotation, and what a failed purge leaves behind.

## Resolution

A **transcript** is Pi's own session file for one stage attempt, retained
inside the job directory, scrubbed once at seal, capped as a runaway-loop
detector rather than a storage policy, and destroyed only by `purge`.

### Location and naming

Fleet passes `--session-dir stages/NN-<kind>/session/` and Pi's own
`--session-id`. Pi names the file itself — `<ISO-timestamp>_<uuid>.jsonl`, under
a per-cwd `--path--` subdirectory — so Fleet **discovers** the file by glob once
at seal and records its resolved job-relative path in `stage.json`. The path is
recorded, never derived.

This strikes `stages/NN-<kind>/logs/pi.jsonl` from
[Specify durable schemas and filesystem layout](03-specify-durable-schemas-and-filesystem-layout.md):
that filename cannot exist, because Fleet does not name the file. Keeping the
transcript under the job directory preserves that ticket's invariant that Fleet
neither reads nor writes outside its four subtrees, and leaves nothing behind in
Pi's global `~/.pi/agent/sessions/` store for `purge` to miss.

### Ceilings

Per **attempt**: 8MB. Per **job**: 32MB. Both in `config.json` under the overlay
pattern [Specify routing and evaluation mechanics](04-specify-routing-and-evaluation-mechanics.md)
settled, so a repository that legitimately needs more raises it without a Fleet
change. The numbers are grounded in observation: the ticket 05 spike's session
file was 17KB and the largest real Pi session on this machine is 685KB, so 8MB
is roughly twelve times any honest stage.

The ceiling is **per attempt, not per stage summed**. Ticket 05's
`sessionName` of `<jobId>-<stageIndex>-<attempt>` already gives each rotation
its own transcript beside the failed one. Summing would throttle a retry in
proportion to how expensively its predecessors failed; the per-job ceiling is
where a stage that keeps burning is caught instead.

### Mid-run enforcement, and why rotation is impossible

Pi holds the session file open and appends to it. Fleet cannot truncate or
rotate a file another process owns without corrupting a session Pi may still
resume, so **rotation is ruled out outright** — the ticket's premise that a
rotation policy exists does not survive contact with the transport ticket 05
chose.

A cap is therefore enforceable only by ending the stage. The supervisor samples
the transcript's size on the poll it already runs; crossing the per-attempt
ceiling terminates the stage through ticket 05's `abort` → SIGTERM → SIGKILL
ladder and classifies it exactly as `stopReason: "length"` is classified — a
**quality failure**: evidence sealed, attempt consumed, rotation to another
model permitted. A runaway transcript is a runaway agent, and the quality-failure
path already knows what to do with one. The partial transcript is retained as
the evidence of what ran away.

### Redaction

Ticket 03 states credentials are "scrubbed as the transcript is written". That
no longer holds: Fleet does not write the file, Pi does, in a detached
subprocess with no write-time hook. Redaction happens at **two** points instead:

1. **At seal**, after `agent_settled` and before `artifact.json` is renamed into
   place, Fleet reads the session file, scrubs known credential shapes, and
   atomically renames the scrubbed copy over the original by the same
   `tmp/` → `fsync` → `rename` → `fsync(dir)` rule as every other write. The
   sealed state is the only state any later reader sees.
2. **At egress**, on every bounded excerpt leaving the module, unchanged from
   ticket 03.

Both are required. Seal-time scrubbing alone trusts one pattern list; egress
scrubbing alone leaves secrets at rest in a stored file.

### Archive fidelity

`archive` **touches no transcript bytes**. It remains the in-place status flip
ticket 03 specified, so every `ArtifactRef` already handed to a caller keeps
resolving. A reduced archival form was rejected: it makes archive destructive
against that guarantee and introduces a second, lossy record type to
schema-version, for space pressure the measured sizes say does not exist —
a hundred archived jobs at observed sizes is well under a gigabyte.

### Store budget

A **soft** per-store budget (default 4GB, configurable) that Fleet reports and
warns on at every admission and in `list`, and that blocks nothing. Automatic
eviction of archived jobs' transcripts is rejected: silent deletion contradicts
`purge` being the only operation that destroys a job record, and would make a
handed-out `ArtifactRef` stop resolving. No ceiling at all is also rejected —
the first signal would be a full disk. Reclamation stays an explicit
primary-orchestrator act.

### Purge ordering and failure

`purge` deletes **transcripts first**, before artifacts and records, updating
`purge-intent.json` as each stage clears. Transcripts are both the largest and
the most sensitive bytes in a job, so a purge that dies halfway has already
destroyed the riskiest part. The tombstone records which stages are cleared, so
a retry with the same short-lived token resumes rather than restarting, and the
partially-purged job stays excluded from `list`, never runnable, exactly as
ticket 03 specified.

### Inspection

`pi --export <session> <out.html>` renders a transcript as HTML. This is a
**documented manual recipe, not a Fleet verb**. Wiring it in would put a second
Pi invocation inside Fleet's surface for a debugging convenience and would emit
an HTML artifact outside the egress redaction path above.

### Vocabulary

`fleet/CONTEXT.md` defined **Stage artifact** as explicitly not a "transcript"
while never defining the transcript. Added both **Transcript** (the retained Pi
session file for one stage attempt — how a stage reached its artifact, never the
artifact, never read to determine an outcome) and **Event stream** (the live RPC
events consumed for classification and usage, then discarded, roughly ten times
larger and carrying nothing the transcript lacks), because that is the
distinction a future reader gets wrong.
