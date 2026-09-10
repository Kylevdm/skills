---
title: "Define the Fleet module interface"
labels:
  - wayfinder:grilling
status: closed
parent: ../../fleet-redesign.md
assignee: "codex"
blocked_by: []
---

## Question

What is the smallest typed interface of the TypeScript Fleet module shared by
the JSON CLI, local stdio MCP adapter, and tests? Decide its operations,
arguments, bounded result envelopes, invariants, error taxonomy, asynchronous
admission semantics, and the line between the module and its Pi, Git,
filesystem, clock, and provider adapters. The interface must preserve explicit
acceptance and landing, forbid generic execution, and hide orchestration policy
from callers.

## Resolution

Fleet is one TypeScript deep module with a typed lifecycle interface. The JSON
CLI and local stdio MCP adapter only translate requests and results. They do
not contain orchestration policy.

```ts
interface Fleet {
  submit(request: SubmitRequest): Promise<Outcome<Admission>>;
  list(query: JobQuery): Promise<Outcome<JobPage>>;
  get(job: JobId): Promise<Outcome<JobView>>;
  report(job: JobId): Promise<Outcome<AcceptanceReport>>;
  diff(request: EvidenceRequest): Promise<Outcome<BoundedEvidence>>;
  checks(request: EvidenceRequest): Promise<Outcome<ChecksReport>>;
  continue(request: ContinuationRequest): Promise<Outcome<Admission>>;
  cancel(request: MutationRequest): Promise<Outcome<JobView>>;
  accept(request: AcceptanceRequest): Promise<Outcome<AcceptanceReceipt>>;
  land(request: LandingRequest): Promise<Outcome<LandingReceipt>>;
  clean(request: MutationRequest): Promise<Outcome<JobView>>;
  archive(request: MutationRequest): Promise<Outcome<JobView>>;
  purge(request: PurgeRequest): Promise<Outcome<PurgePreview | PurgeReceipt>>;
}
```

`SubmitRequest` contains a trusted ticket snapshot or standalone objective, a
validated repository reference, an optional idempotency key, and permitted
execution or routing overrides. It accepts no GitHub credential, shell command,
raw filesystem path, or adapter handle. The GitHub-ingestion ticket owns the
full ticket-snapshot schema.

Fleet generates opaque `JobId` and `ArtifactRef` values. It never exposes
state, worktree, session, or provider paths. `list` returns paginated
`JobSummary` values. `get` returns a compact `JobView`. Report, diff, and check
operations return bounded excerpts and immutable artifact references. Fleet
redacts credentials before returning any result.

The public status is `admitted`, `running`, `waiting`,
`ready-for-acceptance`, `returned-to-orchestrator`, `cancelled`, or `archived`.
The state-machine work may add internal stages without changing these caller
states.

`submit` returns after Fleet durably records the job and schedules detached
work. It does not wait for Pi or return a Pi result. Every later mutation
requires `jobId` and `expectedRevision`; a changed record returns `conflict`.
`accept` requires `ready-for-acceptance`. `land` requires recorded acceptance
and may name only a configured repository target. `archive` requires a
terminal job. `purge` has a preview request that issues a short-lived token and
a confirmation request that repeats it.

`continue` requires explicit primary-orchestrator instructions and an expected
revision. It cannot trigger a silent retry, weaken acceptance requirements, or
create a third quality attempt.

`Outcome<T>` is a discriminated union. Expected failures return a typed Fleet
problem: invalid input, policy denial, conflict, not found, stale confirmation,
unavailable dependency, or capacity limit. Exceptions are reserved for
unexpected faults and process cancellation.

The production composition root supplies Pi, Git, job-store, filesystem,
clock, and provider adapters. Those are private implementation seams. Tests
may construct Fleet with fakes, but the CLI, MCP adapter, and other callers use
only `Fleet`.

### Amendment (2026-09-10)

[Specify routing and evaluation mechanics](04-specify-routing-and-evaluation-mechanics.md)
adds two read-and-maintenance operations to the interface, consumed only by
`fleet-update`:

```ts
evidence(query: EvidenceQuery): Promise<Outcome<RoutingEvidence>>;
probe(request: ProbeRequest): Promise<Outcome<ProbeReport>>;
```

`AcceptanceRequest` also gains an optional field in which the primary
orchestrator states whether it modified the accepted work. Every other decision
in this resolution stands unchanged.

### Amendment (2026-09-10, GitHub ingestion)

[Specify GitHub ingestion and
deduplication](07-specify-github-ingestion-and-deduplication.md) narrows
`SubmitRequest` for ticket-backed jobs. It carries a repository reference, an
issue number, and the primary orchestrator's judgments — risk class,
acceptance-contract additions, permitted overrides — and no ticket content.
Fleet's private GitHub adapter acquires the trusted snapshot itself using
ambient `gh` credentials; the snapshot is not a caller argument. "Accepts no
GitHub credential" stands and now means what it says: no token is ever an
argument. A standalone objective is still supplied directly. Every other
decision in this resolution stands unchanged.

### Amendment (2026-09-10, adapters)

[Design the CLI and MCP adapters](08-design-the-cli-and-mcp-adapters.md) adds
one lifecycle operation, needed by both adapters:

```ts
wait(request: WaitRequest): Promise<Outcome<JobView>>;
```

`WaitRequest` carries a `jobId` and a `timeoutSeconds` clamped to 60. `wait`
blocks until the job reaches `ready-for-acceptance`,
`returned-to-orchestrator`, or `cancelled`, or until the clamp expires, and
always returns a `JobView` — a timeout is `timedOut: true`, never a failure.
It is read-only, takes no `expectedRevision`, and holds no lease. Every other
decision in this resolution stands unchanged.
