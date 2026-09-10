---
title: "Specify routing and evaluation mechanics"
labels:
  - wayfinder:grilling
status: closed
parent: ../../fleet-redesign.md
assignee: "claude"
blocked_by:
  - 02-specify-state-machine-and-recovery-protocol.md
  - 03-specify-durable-schemas-and-filesystem-layout.md
---

## Question

How does Fleet classify risk and select, rotate, fall back between, and
escalate approved models for each role while optimizing primary-orchestrator
tokens first? Decide the registry and telemetry schema, comparable-work
cohorts, least-sampled selection, availability fallback, Go normalized-burn
calculation, DeepSeek peak and off-peak accounting, Qwen's context limit, and
the evidence `fleet-update` consumes without allowing automatic promotions.

## Resolution

Fleet routes every work unit from one **model registry** and records every
attempt in one append-only evidence log. Selection is a deterministic sort, not
a score. No routing position changes without `fleet-update`.

### Registry

The Fleet package ships a default registry, and
`$PI_FLEET_HOME/config.json` carries an optional overlay keyed by model id. A
fresh install routes correctly with no setup; `fleet-update` writes only the
overlay and never edits the package. The overlay is schema-versioned and
validated on read like every other record.

Each registry entry carries `id`, the Pi model string, `provider`, `family`,
`tier`, eligible `roles`, input, output, and cached prices, `rateBands`,
`contextLimit` with any band threshold, `api` (Messages or Chat Completions),
`zeroDataRetention`, and `enabled`. The overlay may set only `tier`, `enabled`,
`roles`, and price corrections.

Prices live in the registry rather than being fetched, so a provider price
change is a `fleet-update` action. A price that changed silently mid-cohort
would corrupt the cost evidence the cohort exists to produce. `family` exists
only to serve the reviewer constraint below.

### Risk class

The caller supplies the risk class in `SubmitRequest`, and Fleet validates it
against cheap structural signals: configured sensitive paths, a snapshot with
no acceptance criteria, a diff budget above a threshold. Fleet may only raise
it. A delegated agent may also raise it and never lower it.

The primary orchestrator has the domain knowledge and has already judged the
work not to be reserved, so it is the right classifier. The raise-only floor
stops a mistaken `low` from routing production-touching work to the cheapest
model in the pool.

### Selection

A **comparable-work cohort** is exactly `(tier, role, riskClass)`. Repository
and language are recorded on every attempt but never routed on: adding them
fragments the counts so far that a ten-attempt threshold would never be met,
and the question the evidence answers — whether a model can perform this role
in Pi — is not repository-specific.

Selection filters the registry to models that are `enabled`, in the required
tier, eligible for the role, not in cooldown, not exhausted, and within their
context band, then applies the reviewer constraint, then sorts on four keys:

1. deprioritized last — currently only a DeepSeek model inside a peak rate band
2. sample count ascending
3. output price ascending
4. registry order

One traceable sort, so a surprising pick can always be explained from a log
line. A cost-weighted score was rejected: it cannot be explained, and its
weights have no evidence behind them.

Peak DeepSeek is therefore chosen only when it is the sole eligible model in
its tier. Peak is seven weekday hours, so DeepSeek still accrues samples across
most of the week.

Reviewers use the writer's tier and a different `family`, as a hard filter. If
that filter empties the eligible set, Fleet drops the constraint, proceeds, and
records the drop. A job must not stall on a heuristic, and escalating a
reviewer a tier to satisfy one spends premium money on the cheapest role to be
wrong about. Frequent recorded drops are a real `fleet-update` signal that the
tier pools are too family-concentrated.

Qwen3.7 Plus is ineligible for a work unit whose estimated input exceeds a
configured margin below its 256K threshold; rotation picks another
standard-tier model. Fleet never silently enters the higher band, because that
contaminates the cost evidence. The estimator's mechanics are deferred — see
the fog patch on the map — since real work rarely approaches 200K.

### Availability

Infrastructure failure splits into two classes. `exhausted` — Go allowance or
DeepSeek wallet — is a funding condition, recorded but excluded from the
failure-rate metric and from cooldown. `auth`, `outage`, `invalid-endpoint`,
and `timeout-before-start` feed both. DeepSeek reporting no credit ten times
says nothing about DeepSeek's coding ability and must not suspend a model that
works.

On infrastructure failure Fleet tries up to three distinct eligible models in
the tier, then escalates a tier. Waiting for provider recovery was rejected:
delegated spend at any tier is cheaper than the primary-orchestrator credits
that a stalled job consumes. When premium's three are also unavailable, the job
returns to the orchestrator with a typed `provider-unavailable` reason rather
than entering `waiting` — if Fleet can run nothing, the primary should learn
that in minutes.

An **availability escalation** is counted separately from the job's one quality
escalation. Settled decision 9 already says an infrastructure failure does not
consume a quality attempt; letting a provider outage move a job up the ladder
and thereby spend its escalation would push work back to the primary, which is
the exact token cost Fleet exists to avoid.

Three consecutive non-exhaustion infrastructure failures put a model in a
configured **cooldown**, default 30 minutes, making it ineligible until the
cooldown lapses. The cooldown is never written to the overlay and heals itself.
It is availability handling, not a routing-position change, so it does not
cross the map's out-of-scope line on automatic promotion. A `probe` failure is
likewise reported for a human decision, never auto-written.

### Evidence

`index/attempts.jsonl` is the authority for routing evidence, appended with
`O_APPEND` exactly as `audit.jsonl` is. `index/routing-stats.json` is a derived
cache, making selection O(1) and rebuildable by replaying the log; a missing or
corrupt cache is a rebuild, never data loss. A mutable stats file as sole
authority was rejected: it would make routing evidence the one thing in the
store a crash can silently destroy.

An attempt record carries the attempt and job identity, stage index, attempt
number, role, risk class, tier, model, provider, rate band, context band,
prompt, cached, and output tokens, `providerRequestId`, wallet cost, computed
Go normalized fraction, timing, outcome, failure class, checks result, reviewer
verdict, escalation cause, `repoId`, language, and an `overridden` flag.

Only attempts reaching a quality outcome — accepted, reviewer-rejected,
checks-failed, or produced nothing — increment the selection sample count.
Infrastructure failures are recorded but do not count: a flaky provider must
not push a model to the back of the rotation and starve the cohort being
filled. Counting only accepted attempts was also rejected, since it would make
a frequently failing model look under-sampled and keep feeding it work.

Attempts made under a user override are recorded with `overridden: true`,
excluded from selection counts, and included in evidence. A human forcing a
model is not the rotation sampling it, but the attempt is still genuine
evidence of that model in that role at that risk class, and this scheme has too
little data to discard any.

Acceptance-time outcomes arrive after a stage is sealed and immutable, so an
`attempt-outcome` record is appended to the same log keyed by attempt id and
joined at evaluation. This also covers a job accepted, archived, and only later
patched by the primary. `AcceptanceRequest` gains an optional field in which
the primary states whether it modified the work; Fleet does not infer it.

Go normalized burn is computed and reported, never routed on. Fleet observes
only its own spend, so its fraction is a systematic under-count of a shared
allowance that interactive use also draws down; a guardrail built on it would
fire at the wrong time in both directions. The real backstop already exists —
allowance exhaustion is an infrastructure failure that rotates without
spending a quality attempt. Direct DeepSeek wallet cost is reported separately
and has no configured ceiling: running dry is a standard failure mode.

`evidence` reports per-cohort maturity as `insufficient`, `provisional`, or
`sufficient` against the settled 10-attempt minimum and 20-attempt preference,
and does nothing else about sparse cohorts. Rotation already fills them as fast
as real work allows, and a cohort that stays empty is stating something true —
that combination does not occur in this workload, so it needs no default.
Steering work toward sparse cohorts was rejected outright: it spends real
quality attempts on data collection.

### Interface amendment

`fleet-update` needs two operations ticket 01 did not define, added as an
explicit additive amendment rather than quiet drift:

```ts
evidence(query: EvidenceQuery): Promise<Outcome<RoutingEvidence>>;
probe(request: ProbeRequest): Promise<Outcome<ProbeReport>>;
```

`evidence` returns aggregated cohort statistics. `probe` runs a small
completion and one representative tool call per candidate, confirming live
availability before `fleet-update` writes an overlay. Letting `fleet-update`
read `index/` and drive Pi itself was rejected: it would put path derivation,
schema versioning, redaction, and provider knowledge into a skill, the exact
coupling ticket 01 was written to prevent, and would break the skill on every
store migration. They are two operations rather than one because `evidence` is
cheap and read-only while `probe` spends real money, and the CLI and MCP
adapters must treat them differently.
