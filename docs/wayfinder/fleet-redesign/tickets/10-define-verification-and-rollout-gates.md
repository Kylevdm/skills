---
title: "Define verification and rollout gates"
labels:
  - wayfinder:grilling
status: closed
parent: ../../fleet-redesign.md
assignee: "claude"
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

## Resolution

Verification is a **fixed ladder of standing suites**; rollout is a **staircase
of four autonomy stages**. A build ticket names the rungs it extends and never
defines its own notion of done — a bespoke per-ticket gate cannot catch a
regression a later ticket causes.

Spec: [assets/10-verification-and-rollout-gates/spec.md](../assets/10-verification-and-rollout-gates/spec.md)

### The ladder

Rung 0 `tsc --noEmit`, rung 1 fixtures over the faked Pi and GitHub seams,
rung 2 real-worktree invariants, rung 3 adapter conformance, rung 4 live Pi
smoke plus fixture-drift check, rung 5 module evals. Rungs 0-3 are hermetic and
run in GitHub Actions on push and PR; rungs 4 and 5 are hand-run and never
reach CI, because a public repo must not be able to spend the maintainer's
allowance from a pull request.

Real filesystem, real git, real child processes — ticket 03's rename-commit
semantics and ticket 06's namespace rule are the properties under test, and a
fake would paper over exactly them. Only Pi and GitHub are faked: Pi as a
scriptable stub replaying the ticket 05 spike's captured event stream, GitHub
as recorded issue snapshots. The stub is substituted through one resolved
`piBinary`, recorded in the call intent with the detected Pi version, so an
attempt record always says which binary produced it.

Rungs 1 and 2 each carry a **frozen manifest of named tests** (twelve and ten
respectively, listed in the spec), each traceable to the ticket that decided
it. A missing test is as red as a failing one; a new invariant means a new
named test.

Rung 3 is one suite parameterised over both adapters, not two suites — a
contract tested twice drifts.

Test runner is `node:test` with no dependencies, under the same
`--experimental-strip-types` flag as `bin/fleet`: a runner with its own
transform pipeline reintroduces the staleness that the no-build-step premise
exists to prevent.

### The staircase

S0 hand-submitted only, S1 primary may delegate at `low` risk with concurrency
1 in one repo, S2 `standard` risk across two repos, S3 automatic delegation as
the default. Advances need 5, 10 and 20 accepted jobs respectively, with
acceptance judged by the human rather than by Fleet's own reviewer verdict,
plus a clean `probe` of every enabled model. `probe` is a stage-advance gate
rather than a ladder rung, since it spends real money per candidate.

**Ticket 09's step-5 deletion commit is the S0 → S1 advance** — same evidence,
one event. S0 is hand-submitted only, so the frozen `fleet.sh` costs nothing by
still existing; after the commit the fallback is the `pre-fleet-ts` revert.

Halt (acceptance below 60% over 5 jobs, 2 consecutive same-class returns, or
$5 of delegated spend in a day) demotes one stage and re-advancing runs the
full advance criteria again on a reset window. Abort is reserved for the
integrity class — a ref outside the namespace, a write outside the four
subtrees, record loss — where Fleet refuses admission and the human runs the
rollback. Fleet never uninstalls itself unattended.

Pilot limits live in a `pilot` block in `$PI_FLEET_HOME/config.json`, a sibling
of the registry overlay and outside `fleet-update`'s reach, enforced at
admission with `policy-denied` naming the limit hit. The active stage is
stamped on every attempt record, and `fleet evidence --stage-report` computes
the advance and halt numbers from the log — a gate a human has to tally stops
being run around S2.

### Warnings reach the primary

The one place this ticket touches the runtime contract rather than the test
suite. Eight typed warning codes on the envelope, five of which derive
`reviewDepth: "elevated"`, meaning the primary reads the diff itself instead of
accepting on summary plus green checks.

### Amends three closed tickets

- [Design the CLI and MCP adapters](08-design-the-cli-and-mcp-adapters.md): the
  envelope gains `warnings: []` and `reviewDepth`.
- [Specify routing and evaluation mechanics](04-specify-routing-and-evaluation-mechanics.md):
  the attempt record gains the active pilot stage; `evidence` gains
  `--stage-report`.
- [Plan TypeScript packaging and migration](09-plan-typescript-packaging-and-migration.md):
  its step 5 is identified as the S0 → S1 advance.

### Defers one decision

Every gate that mentions checks runs the repository's real check command, and
no closed ticket says where that command comes from. Graduated as [Specify
check-command discovery and the checking stage
contract](16-specify-check-command-discovery.md) rather than folded in here,
since it is a runtime spec decision and not a gate.

## Amendment (2026-09-10, check-command discovery)

[Specify check-command discovery and the checking stage
contract](16-specify-check-command-discovery.md) resolves the decision this
ticket deferred, and grows the warning-code set from eight to eleven:
writer-reported-green against a red Fleet run, a check that hit its timeout,
and a job admitted under `checks: none`. All three derive
`reviewDepth: "elevated"` — each means the green signal the primary would
otherwise accept on is absent or untrustworthy.
