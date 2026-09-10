---
title: "Fleet redesign around primary-token savings"
labels:
  - wayfinder:map
status: open
tracker: local-markdown
children: docs/wayfinder/fleet-redesign/tickets
---

## Destination

Produce an implementation-ready specification and ordered migration plan for
Fleet. It must automatically delegate suitable work when that is expected to
save Codex or Claude primary-orchestrator tokens, collect compact evidence for
primary acceptance, and return work after one escalation when delegated work
does not meet the contract.

## Notes

This map plans the redesign. It does not implement it. The settled decisions in
`/tmp/fleet-wayfinder-handoff.md` are fixed unless repository evidence makes
one impossible. `fleet/CONTEXT.md` supplies the domain language.

This repository has no usable remote tracker configuration, so this map uses
the local-Markdown tracker. Child tickets are in
`docs/wayfinder/fleet-redesign/tickets/`; their front matter records claims and
blocking. An open ticket with an empty `assignee` and no open `blocked_by`
ticket is on the frontier.

From [Plan TypeScript packaging and migration](fleet-redesign/tickets/09-plan-typescript-packaging-and-migration.md)
onward the module's home is the public `Kylevdm/pi-fleet` repo, and this map
moves onto its issue tracker at map agreement — see
[Migrate the map to GitHub issues](fleet-redesign/tickets/15-migrate-the-map-to-github-issues.md).
`fleet/scripts/fleet.sh` is **frozen** as of 2026-09-10: still runnable, no
further edits.

Use `grilling` and `domain-modeling` for grilling tickets, `prototype` for
prototype tickets, and `codebase-design` for the Fleet module interface. Use
`unslop` for written artifacts. Consult `writing-for-agents` and
`skill-creator` only when a ticket reaches Fleet skill design. Treat
`fleet-update` as a maintenance surface to redesign, not as the current
implementation authority.

## Decisions so far

<!-- Closed ticket summaries belong here. Each links to its ticket. -->

- [Define the Fleet module interface](fleet-redesign/tickets/01-define-fleet-module-interface.md): Fleet has one typed lifecycle interface, bounded opaque results, durable asynchronous admission, explicit acceptance and landing, and private implementation adapters.
- [Specify the state machine and recovery protocol](fleet-redesign/tickets/02-specify-state-machine-and-recovery-protocol.md): One fenced-lease state machine resumes only after sealed stages, reconciles in-flight calls once, and returns unsafe work to the primary.
- [Specify durable schemas and filesystem layout](fleet-redesign/tickets/03-specify-durable-schemas-and-filesystem-layout.md): One mutable revisioned `job.json` per job over a write-once record set, rename-committed writes, artifact presence as the seal, and call intent recorded before any paid call.
- [Specify routing and evaluation mechanics](fleet-redesign/tickets/04-specify-routing-and-evaluation-mechanics.md): One shipped registry with a `fleet-update` overlay, a four-key deterministic sort over `(tier, role, riskClass)` cohorts, availability escalation that never spends a quality attempt, and an append-only evidence log that only `fleet-update` acts on.
- [Specify the Pi work-unit protocol](fleet-redesign/tickets/05-specify-the-pi-work-unit-protocol.md): Fleet drives one detached `pi --mode rpc` subprocess per stage, gated by a single Fleet extension, sealing each stage on a terminating `submit_*` tool call; verified live.
- [Specify Git isolation, assembly, refresh, and landing](fleet-redesign/tickets/06-specify-git-isolation-assembly-refresh-and-landing.md): Fleet never writes a ref outside `refs/heads/fleet/<jobId>/`, assembles from the pinned base with one delegated integration rung, refreshes a moved target by rebase plus re-check only, and `land` produces a fast-forwardable candidate branch rather than moving the target ref.
- [Specify GitHub ingestion and deduplication](fleet-redesign/tickets/07-specify-github-ingestion-and-deduplication.md): Fleet fetches its own trusted snapshot from a bare issue reference, uses native GitHub relations only, refuses admission on an open blocker, and holds the dedup key through acceptance.
- [Design the CLI and MCP adapters](fleet-redesign/tickets/08-design-the-cli-and-mcp-adapters.md): Two thin translators over one module, a single result envelope carrying the legal `next` calls, hand-back by a 60-second `wait` long-poll that wakes only on actionable states, confirmation inside Fleet for `purge` alone, and a clean break from the shell CLI (legacy-job support since struck by ticket 09).
- [Plan TypeScript packaging and migration](fleet-redesign/tickets/09-plan-typescript-packaging-and-migration.md): Fleet moves to a standalone public `Kylevdm/pi-fleet` repo, runs from source with no build step, registers over each host's own config surface, migrates nothing because legacy support is removed outright, and cuts over in one deletion commit that is revertible.
- [Define verification and rollout gates](fleet-redesign/tickets/10-define-verification-and-rollout-gates.md): A fixed six-rung verification ladder (rungs 0-3 hermetic in CI, live Pi smoke and evals hand-run) with frozen manifests of named invariant tests, and a four-stage autonomy staircase whose S0 → S1 advance *is* ticket 09's deletion commit; halt demotes a stage, abort is reserved for integrity failures.
- [Specify transcript retention and purge](fleet-redesign/tickets/11-specify-transcript-retention-and-purge.md): Pi's own session file per stage attempt, kept in the job directory under a discovered path, scrubbed at seal and at egress, capped at 8MB per attempt as a runaway detector rather than rotated, full-fidelity through archive, and deleted transcripts-first by purge.
- [Specify the input-token estimator](fleet-redesign/tickets/12-specify-the-input-token-estimator.md): A crude pre-dispatch tripwire — assembled bytes over 3.5, eligible below half the model's limit — justified by feasibility rather than Qwen's band, calibrated against real usage, returning `input-too-large` when nothing fits and recording a band violation when it was wrong.
- [Gate git subcommands for delegated writers](fleet-redesign/tickets/13-gate-git-subcommands-for-delegated-writers.md): The git gate is an explicit guardrail, not a boundary — deny-by-default subcommands, refused relocating flags, blocked `.git` writes, fixed and non-overlayable — while a whole-repository ref diff around every bash-holding stage is what actually protects the namespace invariant, and a detected movement returns the job rather than retrying or repairing it.
- [Create the pi-fleet public repository](fleet-redesign/tickets/14-create-the-pi-fleet-public-repo.md): `Kylevdm/pi-fleet` now exists — public, MIT, issues enabled, README-only — cloned and pushed from the fixed `npm link` path `~/pi-fleet`.

## Not yet specified

- Whether `to-tickets` publishes blockers and parentage as GitHub's native
  `sub_issues` and `dependencies/blocked_by` relations.
  [Specify GitHub ingestion and deduplication](fleet-redesign/tickets/07-specify-github-ingestion-and-deduplication.md)
  made native relations the only source Fleet reads, so a tracker that still
  writes them as prose silently produces unblocked-looking tickets. The fix
  belongs on the `to-tickets` side, and the migration plan may need to carry it.
  Same patch covers relation availability on hosts other than github.com.
  [Migrate the map to GitHub issues](fleet-redesign/tickets/15-migrate-the-map-to-github-issues.md)
  now tests relation availability first-hand on `pi-fleet`; its finding decides
  whether this patch graduates into a `to-tickets` ticket or dissolves.

## Out of scope

- Depending on or copying `agent-pi`. It is precedent only.
- Local Ollama routing in the first release. `docs/fog.md` owns its follow-up.
- Containerized or process-sandboxed workers in the first release.
- Automatic tier promotion or scheduled `fleet-update`.
- GitHub issue mutation, pushing, or closing by Fleet.
- Replacing project-level release reviews.
