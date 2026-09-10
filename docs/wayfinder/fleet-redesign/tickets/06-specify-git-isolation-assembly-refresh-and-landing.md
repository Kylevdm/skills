---
title: "Specify Git isolation, assembly, refresh, and landing"
labels:
  - wayfinder:prototype
status: closed
parent: ../../fleet-redesign.md
assignee: "claude"
blocked_by:
  - 02-specify-state-machine-and-recovery-protocol.md
  - 03-specify-durable-schemas-and-filesystem-layout.md
  - 05-specify-the-pi-work-unit-protocol.md
---

## Question

Which Git operations and safety rules implement one writer for a ticket-backed
job and deterministic assembly for a standalone discovery job? Decide worktree
and branch naming, ownership enforcement, commit collection, assembly order,
integration escalation, pinned-base and current-target validation, dirty-tree
handling, refreshed evidence and acceptance, clean, archive, purge, and the
exact conditions that return a job instead of landing it.

## Resolution

Fleet owns one branch namespace and never leaves it. Worktrees are
`~/.pi/fleet/worktrees/<jobId>/<role>-<n>/`, branches are
`fleet/<jobId>/<role>-<n>` with `assembly` and `landed` reserved, and **Fleet
never writes a ref outside `refs/heads/fleet/<jobId>/`** — no exceptions,
including at landing. One writer per ticket-backed job is enforced twice over:
ticket 02's repository writer lease, and the namespace itself. The reviewer gets
the second worktree ticket 05 deferred here, `--detach` at the writer's sealed
sha, so it provably judges the sealed commit.

Assembly cuts from the pinned base, cherry-picks each sealed writer commit in the
planner's declared order, and re-checks the assembled tree — a green check per
isolated commit is not evidence the assembly is green. A conflict climbs exactly
one rung: a delegated `integrating` stage scoped to that conflict plus a mandatory
re-check, then return. That attempt is budgeted separately from the two quality
attempts, because a textual conflict indicts the planner's decomposition, not the
writer's work.

Before landing, `validating-current-target` compares the target tip to the pinned
base. A moved target is rebased in a Fleet worktree and **re-checked only** —
delegated review is not re-run, since a clean rebase leaves the diff the reviewer
judged unchanged and review is the expensive stage. A conflicting rebase returns
the job; refresh gets no integration rung, because unlike a decomposition conflict
Fleet has no context on the unrelated work it collided with. If the target moves
*again* during the refreshed check, the job returns immediately — no retry cycle,
whose cost is invisible until it has been paid and which a busy branch can starve
regardless.

`land` therefore produces a **landing candidate**, not a landed branch:
`fleet/<jobId>/landed`, rebased onto the validated tip with refreshed checks green,
for the primary orchestrator to fast-forward or merge. Fleet moves no ref, merges
nothing, pushes nothing, and touches no GitHub issue. Beyond keeping the namespace
rule absolute, this is forced mechanically — git will not let two worktrees check
out the same branch, so with the target checked out in the user's worktree Fleet
*cannot* land on it except by writing the ref behind the user's HEAD, the exact
invisible action the rule forbids. The record stores the sha the candidate was
fast-forwardable from; if the target has moved past it, the fast-forward fails in
the orchestrator's hands, where the context to resolve it lives.

Fleet never requires a clean user checkout and never runs a writing git command in
it — every Fleet git write happens in a Fleet-owned worktree, so an unrelated dirty
file can never block a job. `clean` removes worktrees and keeps every branch, since
the commits are the work; `archive` does nothing git-side; only `purge` deletes
branches, behind ticket 03's unlanded-branch acknowledgement. The accepted cost is
that `refs/heads/fleet/*` accumulates until purged.

Spec: [assets/06-git-lifecycle/spec.md](../assets/06-git-lifecycle/spec.md)
