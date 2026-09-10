---
title: "Specify GitHub ingestion and deduplication"
labels:
  - wayfinder:grilling
status: closed
parent: ../../fleet-redesign.md
assignee: "claude"
blocked_by:
  - 01-define-fleet-module-interface.md
  - 02-specify-state-machine-and-recovery-protocol.md
  - 03-specify-durable-schemas-and-filesystem-layout.md
---

## Question

How does Fleet admit a GitHub child ticket without granting GitHub authority to
delegated agents or mutating issues itself? Decide trusted snapshot acquisition,
parent and blocker representation, blocker refresh, credential separation,
repository identity, active-job deduplication, standalone-request discovery,
and the exact oversized-job return path.

## Resolution

Fleet acquires its own GitHub context. `SubmitRequest` carries a repository
reference, an issue number, and the primary orchestrator's judgments — risk
class, any additions to the acceptance contract, permitted overrides — but no
ticket content. Fleet's GitHub adapter then fetches the snapshot itself using
ambient `gh` credentials inside the Fleet process.

The primary still reads the issue: it must, to decide the work is not reserved
and to set the risk class that [Specify routing and evaluation
mechanics](04-specify-routing-and-evaluation-mechanics.md) already assigned to
the caller. What this removes is the primary *re-emitting* what it read as a
bespoke payload — output tokens spent transcribing something Fleet can fetch at
a fidelity it can verify. Ticket 04's validation of risk class against "a
snapshot with no acceptance criteria" only works if Fleet holds the snapshot,
so this is the division that work already assumed.

Delegated agents receive no GitHub credentials, no `gh`, and no Fleet-control
tools. They see the sealed snapshot as text.

Recorded as `fleet/docs/adr/0003-fleet-owns-github-access.md`.

### Repository identity

Fleet resolves a canonical identity once at admission, in order: the GitHub
GraphQL node id (survives rename and transfer), else the normalized remote
`github.com/<owner>/<name>` lowercased, else the realpath of the repository
root for a repository with no remote. `repoId` is the first 16 hex characters
of the sha256 of that string — fixed width and safe as the path segment
`capacity/writers-<repoId>.json`. `job.json` records the human-readable
identity and which rule produced it, so `list` can show `Kylevdm/skills`.

### Snapshot composition

The issue in full: title, body, labels, state, author, timestamps. Its comments
in order, excluding authors of type `Bot` by default with a config escape
hatch, since CI chatter is the bulk of a long thread and carries almost no
intent. The parent issue's title and body only, never its comments — the parent
supplies scope context, and `to-tickets` has already pushed actionable detail
into the child. Each blocker's title, state, and body.

Bounds: the first comment plus the most recent 50, any single comment truncated
at 4KB with an explicit elision marker, the whole snapshot capped near 256KB.
Attachment and image URLs are recorded, never fetched — they are usually
auth-gated and the delegated agent holds no credential to follow them.

### Relations

Parent and blocker relations come from GitHub's native relations only:
`sub_issues`, the GraphQL `parent` field, and `dependencies/blocked_by`. All
three were verified live against this repository's token on gh 2.45.0. Fleet
does not parse task lists or "Blocked by #N" prose: false negatives are silent
and start a writer on unfinished ground, and the fix for a tracker that
publishes blockers as prose belongs in `to-tickets`. The raw body still reaches
the writer as text; it just does not gate admission. Blockers are followed one
level deep in the same repository; a cross-repository blocker is recorded by
reference and not fetched.

### Snapshot content is untrusted

Issue and comment text is third-party input that becomes agent brief input.
Fleet fences it structurally: snapshot content enters the brief inside an
explicitly delimited block labelled as quoted issue-tracker material rather
than instructions, with the acceptance contract and scope stated outside that
block. Each comment records its author and association (`OWNER`, `MEMBER`,
`NONE`). There is no content filtering or injection heuristic — those fail
quietly and breed false confidence. The guarantee remains the capability
boundary: no credentials, no Fleet-control tools, and the git subcommand gate
from [Gate git subcommands for delegated
writers](13-gate-git-subcommands-for-delegated-writers.md). The fencing makes
that boundary legible rather than pretending to be a second one.

### Deduplication

`index/active.json` keys `(repoId, issueKey)` to a `jobId`. The entry is held
through every non-terminal state and through `ready-for-acceptance`, so
unaccepted work on a branch never gets a second writer racing it. It is
released on `cancelled`, `archived`, and `returned-to-orchestrator`, because
re-scoping and resubmitting is the primary's whole recourse after a return. A
colliding `submit` returns the typed `conflict` problem naming the holding
`jobId`, unless its `idempotencyKey` matches, which returns the original
`Admission`. A submit taking a key a returned job recently released carries the
prior `jobId` in its `Admission` as a non-fatal note.

A standalone objective has no issue key, so similarity is textual and
deterministic: normalize the objective, then compare word-trigram Jaccard
similarity against active standalone jobs in the same `repoId` only. An exact
normalized match deduplicates like an idempotency hit; anything above a
configured 0.6 returns a non-fatal `similarTo` list of job ids and titles. No
model call and no embedding store on the admission path.

### Blocker refresh

[Specify the state machine and recovery
protocol](02-specify-state-machine-and-recovery-protocol.md) closed the
`waiting` reason set to `capacity`, `provider-recovery`, and
`primary-instructions`, so a job with open blockers has nowhere to park. An
open blocker at admission is therefore a typed policy denial: `submit` refuses
and creates no job record. Fleet is not a queue.

Blockers are re-checked exactly once more, at the start of the `writing` stage.
A blocker reopened in the interval returns the job with reason
`blocker-reopened` before a writer attempt is spent. There is no re-check after
writing — a blocker reopening mid-write should not torch completed work.
Instead the acceptance report re-states each blocker's state with its fetch
timestamp, so the primary sees the ground shifting at the moment it decides.

### Ingestion failure

All ingestion happens before admission. `admitted` records the immutable input
snapshot, so there is no coherent job without one; a failure returns a typed
Fleet problem and leaves no job record and no index entry. Not-found and
no-access map to `policy denial`. Rate limits, 5xx, and network failures map to
`unavailable dependency` after a bounded adapter retry — three attempts,
exponential backoff, under 30 seconds total — so a flap never reaches the
primary as a decision. The added `submit` latency does not violate the
asynchrony rule in [Define the Fleet module
interface](01-define-fleet-module-interface.md), which is about not waiting on
Pi.

The issue, repository identity, and blockers are fatal to miss. The parent is
not: a deleted, moved, or newly-private parent is recorded as `unavailable` and
admission proceeds, because the parent is scope context rather than a gate.

### Staleness

The snapshot is authoritative for the whole job lifetime. It is never
re-fetched and never patched, because a brief that moves under a resumed
supervisor breaks the guarantee sealed stages bought. Every fetched object
records its `updatedAt` and node id. At acceptance-report time only, Fleet makes
one cheap metadata re-check — timestamps, no bodies — and sets `snapshotStale`
with what moved. It never auto-refreshes and never auto-returns. A genuinely
re-scoped ticket becomes a new job, not a mutated one; `continue` carries
primary instructions, not a new snapshot. The cost is that a typo fix in a
ticket body can orphan an in-flight job's fidelity; the benefit is that "what
was this agent actually told?" always has exactly one answer.

### Oversized return

Oversize is detected at the end of `planning`, not at admission — admission
sees only the snapshot, and "this needs three writers" is a judgment about the
repository. The planner's sealed artifact carries `writersRequired`. Any value
above 1 on a ticket-backed job seals that artifact and returns the job with
reason `oversized`, spending no writer attempt and no quality attempt. The
return payload carries the planner's proposed decomposition as evidence,
explicitly not as tickets: Fleet mutates no GitHub issue, so the primary reads
the proposal and decides whether to hand it to `to-tickets`. The expensive
judgment is paid for by a cheap agent; the tracker mutation stays reserved.
