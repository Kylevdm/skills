---
title: "Specify the state machine and recovery protocol"
labels:
  - wayfinder:grilling
status: closed
parent: ../../fleet-redesign.md
assignee: "codex"
blocked_by:
  - 01-define-fleet-module-interface.md
---

## Question

Which complete job and stage states, transitions, ownership leases,
idempotency rules, timeout paths, cancellation behavior, and terminal-state
continuations implement Fleet's durable detached state machine? Decide exactly
how a supervisor resumes after the last sealed stage, distinguishes
infrastructure failures from quality attempts, prevents implicit paid repeats,
coordinates global capacity, and returns a job to the primary orchestrator.

## Resolution

Fleet uses one durable job state machine. A job declares either the `direct`
or `discovery` path at admission. Both paths use the same stage protocol,
recovery rules, cancellation behavior, evidence, and terminal states. The
discovery path may schedule read-only scouting and planning before writing;
the direct path begins its writer stage after preparation.

The public states remain `admitted`, `running`, `waiting`,
`ready-for-acceptance`, `returned-to-orchestrator`, `cancelled`, and
`archived`. `admitted` records the immutable input snapshot, selected path,
risk class, acceptance contract, ordered stage plan, and pinned base. The
supervisor then moves it to `running`.

A running job has one current internal stage: `preparing`, `scouting`,
`planning`, `writing`, `checking`, `reviewing`, `assembling`,
`validating-current-target`, or `cancelling`. A stage moves through `planned`,
`active`, and `sealed`. Fleet seals an immutable stage artifact before it
advances. A sealed stage never runs again. `checking`, `reviewing`, and
`validating-current-target` must seal passed evidence before a job can become
`ready-for-acceptance`.

`waiting` represents a durable pause rather than an active provider call. Its
recorded reason is one of `capacity`, `provider-recovery`, or
`primary-instructions`. The job returns to `running` only when the recorded
condition clears and the current supervisor holds the job lease. Work that
needs a reserved decision, exceeds its allowed shape, has a second quality
failure, cannot safely reconcile an in-flight call, fails assembly or
current-target validation, or reaches its three-hour job deadline moves to
`returned-to-orchestrator` with a typed reason and the available evidence.

Each active job has an expiring fenced supervisor lease with `owner`,
`generation`, and `expiresAt`. A supervisor renews the lease while it is
active. Every job, stage, and capacity write includes the current generation;
the store rejects a write from an expired or superseded lease. A replacement
supervisor may claim a job only after expiry plus a configurable 30-second
grace period. The claim increments the generation and starts at the last
sealed stage. Detached per-job supervisors plus these leases provide the
required recovery guarantees. This design does not require a long-lived
scheduler.

Before Fleet starts an external Pi call, it atomically persists a call intent
with the stage, lease generation, timeout, provider request identity, and any
session identifier available at launch. Recovery reconciles that exact process
or session once. If it can obtain a completed result, Fleet validates and
seals it. If the process is still live, the recovered supervisor resumes
watching it. If Fleet cannot identify or safely recover the result, it returns
the job to the primary orchestrator. It never repeats a paid call implicitly.

An `idempotencyKey` deduplicates `submit` requests to the original admission.
All later mutations require `expectedRevision`; Fleet increments the revision
on each accepted mutation and returns `conflict` on a stale request. Terminal
transitions are idempotent when the requested terminal outcome matches the
recorded one. Other terminal mutations return a typed state conflict.

Fleet distinguishes outcomes at the stage boundary. Authentication failures,
provider outages, allowance exhaustion, and invalid endpoints are
infrastructure failures. Fleet records their time and cost, then tries another
approved model in the same tier when the job and stage deadlines allow. It
does not spend a quality attempt. A timeout after an agent has started,
invalid or irrelevant output, failed required checks, scope or contract
violations, and reviewer rejection are quality failures. A quality failure
seals its evidence and consumes one attempt. Fleet makes one escalation to the
next allowed tier; a second quality failure returns the job to the primary
orchestrator. There is no repair turn or third delegated attempt.

Fleet acquires durable capacity leases only when it admits a constrained role
to an active stage. A writer needs both a global writer lease and a repository
writer lease. The initial limits are three global writers and one writer per
repository. Scouts, planners, reviewers, and jobs waiting for capacity or
primary instructions do not hold writer capacity. The configuration may give
those roles independent limits. Lease expiry returns capacity after a crashed
supervisor; fenced writes stop a stale supervisor from using reclaimed work.

Cancellation moves a job through internal `cancelling`, stops the identified
Pi process, seals all recoverable evidence, releases capacity leases, and
preserves branches and records. A confirmed cancellation becomes the public
terminal state `cancelled`. If process termination cannot be confirmed before
the cancellation deadline, Fleet records that fact, fences the job from further
transitions, and still marks it `cancelled`; a later recovery attempt may only
collect evidence or verify termination, never resume work. `clean` and
`archive` retain this record under their existing rules.

## Amendment (2026-09-10)

[Specify check-command discovery and the checking stage
contract](16-specify-check-command-discovery.md) qualifies two rules above.

The requirement that `checking` seal passed evidence before
`ready-for-acceptance` is **conditional on the stage plan containing a
`checking` stage**. A repository configured `checks: none` omits the stage
entirely rather than sealing a vacuous pass, and carries a warning code and
elevated review depth instead.

Failure of the configured `setup` command list — the per-worktree dependency
preparation that precedes the checks — joins the **infrastructure** class: a
missing lockfile or an unreachable registry is not the writer's doing and
spends no quality attempt.
