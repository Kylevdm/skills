---
title: "Define verification and rollout gates"
labels:
  - wayfinder:grilling
status: open
parent: ../../fleet-redesign.md
assignee: ""
blocked_by:
  - 04-specify-routing-and-evaluation-mechanics.md
  - 05-specify-the-pi-work-unit-protocol.md
  - 06-specify-git-isolation-assembly-refresh-and-landing.md
  - 07-specify-github-ingestion-and-deduplication.md
  - 08-design-the-cli-and-mcp-adapters.md
  - 09-plan-typescript-packaging-and-migration.md
---

## Question

Which verification fixtures, fake adapters, real-worktree integrations,
adapter contracts, provider preflights, skill evaluations, acceptance criteria,
and rollout stages prove the redesign before automatic delegation becomes the
default? Decide the evidence each gate requires, the safe pilot limits, how
warnings and escalations alter primary review, and the criteria for halting or
rolling back the rollout.

## Inherited scope (2026-09-10)

[Plan TypeScript packaging and migration](09-plan-typescript-packaging-and-migration.md)
fixes the cutover *sequence* — freeze the script, build greenfield, link and
register, verify on both hosts, then one deletion commit — and leaves the gate
criteria here. Two constraints it hands over:

- Verification is **incremental**: the module is tested as each build ticket
  lands, not once at the end. Gates must therefore be per-stage, not a single
  pre-cutover checklist.
- There is no side-by-side comparison against `fleet.sh` to gate on. The two
  share no records and the script is frozen, so every gate is the module
  proving itself against ticket 05's verified Pi protocol.

The step-4 tag `pre-fleet-ts` plus `npm unlink` / `fleet mcp uninstall` is the
whole rollback surface; there is no data state to reverse. A gate that assumes
a reversible migration is over-specified.
