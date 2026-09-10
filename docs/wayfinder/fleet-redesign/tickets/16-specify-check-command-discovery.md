---
title: "Specify check-command discovery and the checking stage contract"
labels:
  - wayfinder:grilling
status: closed
parent: ../../fleet-redesign.md
assignee: "kylevdm"
blocked_by: []
---

## Question

Where does the check command come from, and what exactly must the `checking`
stage seal? [Specify the state machine and recovery
protocol](02-specify-state-machine-and-recovery-protocol.md) requires
`checking` to seal passed evidence before a job can reach
`ready-for-acceptance`, and [Specify Git isolation, assembly, refresh, and
landing](06-specify-git-isolation-assembly-refresh-and-landing.md) re-checks
after assembly and after a refresh rebase — but no closed ticket says how the
command is discovered.

Decide: whether it is repository config, planner-declared, detected from the
repository (`package.json` scripts, a Makefile target), or supplied in
`SubmitRequest`; how a repository with no check command is admitted, if at all;
what `out/checks.json` records; whether check failure is a quality failure that
consumes an attempt; and whether the writer's own `commandsRun` count as
checks or only Fleet's independent run does.

## Why it exists

Surfaced by [Define verification and rollout
gates](10-define-verification-and-rollout-gates.md), which requires every gate
to run the repository's real check command and found that nothing specifies it.
The acceptance rates in that ticket's stage-advance criteria are meaningless
until this is settled.

## Resolution

`checking` is a **stage without a model**. Fleet runs a human-configured
command list as its own child process and seals the exit codes; no Pi call, no
registry lookup, no capacity lease. A model between the command and the
evidence would add cost, non-determinism and a fabrication surface to the one
part of the loop whose whole value is that nobody could have talked it into
passing.

### Where the command comes from

A per-repository `checks` block in `$PI_FLEET_HOME/config.json`, keyed by
ticket 07's `repoId`, with an optional default block. It is **human-owned and
outside `fleet-update`'s reach**, a sibling of ticket 10's `pilot` block:
`fleet-update` routes models on evidence that says nothing about check
commands, and rewriting the argv Fleet executes is a far larger blast radius
than reordering a registry.

Planner-declared and `SubmitRequest`-supplied commands are both refused. Ticket
01 already bars a shell command from `SubmitRequest`, and ticket 05's command
gate exists precisely so the delegated side never chooses an argv. The command
is the one thing in the loop the delegated side must not pick.

Detection **proposes, never defaults**. `checks --detect <repo>` is a
read-only operation that reads `package.json` scripts, a `Makefile` and common
runner configs and returns a proposed block for a human to confirm into config;
Fleet writes nothing itself. It belongs at S0 on ticket 10's staircase, which
is exactly when a human is watching.

The block holds `setup` and `checks`, both ordered lists of argv arrays.
**Every check runs — no fail-fast — and the job passes only if every exit code
is 0. Exit code is the sole pass criterion**; Fleet never parses output, which
is per-runner, drifts, and would hand the delegated side a formatting attack. A
writer that broke types *and* tests gets both facts in one escalation brief
instead of finding the second only after fixing the first.

`setup` runs once per worktree, before the checks. **Its failure is an
infrastructure failure** under ticket 02 — no quality attempt spent, because a
missing lockfile or a down registry is not the writer's doing. Symlinking the
user's `node_modules` was rejected as breaking worktree isolation; folding
`npm ci` into the check command was rejected because it makes a registry
outage read as a code failure, the exact misclassification ticket 02 works to
prevent.

### No check command

Admission is **refused** by default — `policy-denied`, reason
`no-check-command`. Ticket 10's acceptance rates and its S1 → S3 advance
criteria are noise without a real check. The single escape is `checks: none`
written deliberately in config, which **omits the `checking` stage from the
stage plan** rather than sealing a vacuous pass: a green artifact on disk for a
job nobody checked is worse than a visible gap, because `--stage-report` would
count it as evidence. Ticket 02's rule reads as written — *if* the plan
contains a `checking` stage it must seal passed evidence. The omission is
visible in the plan itself, and the job carries a warning code and elevated
review depth.

### Evidence, not self-report

**The writer's `commandsRun` is transcript, never evidence.** Only Fleet's own
run, in a Fleet-owned worktree, populates `out/checks.json` and satisfies
ticket 02's sealed-passed-evidence rule. A writer claiming `contractMet: true`
against a red Fleet run earns its own warning code — that discrepancy is a
signal about the model, not a detail of the job.

The writer is **told the command list** as job-level brief context. Judging a
writer against a command it was never shown manufactures quality failures and
burns escalations on a knowledge gap rather than a capability gap; it is also
what gives the discrepancy code its teeth.

### Each check is its own stage

Every check runs in a Fleet-owned worktree, never the user's checkout, and each
of ticket 06's three check points seals its **own** `stages/NN-checking/` entry:
ticket 02 says a sealed stage never runs again, so a re-check must be a new
stage or the model breaks. The record names the commit judged and the trigger —
`post-write`, `post-assembly`, `post-refresh` — which is what lets ticket 10's
`--stage-report` distinguish *writers ship red code* from *this branch is too
busy to land against*.

Red is classified by who caused it:

- **post-write** — a writer quality failure, consumes an attempt, one escalation.
- **post-assembly** — indicts decomposition, feeds ticket 06's single
  `integrating` rung on its separate budget.
- **post-refresh** — returns the job immediately; ticket 06 gives refresh no
  rung and Fleet has no context on the unrelated work it collided with.

A per-command timeout (default 10 minutes) bounds each command inside the stage
deadline, terminating by ticket 05's ladder (`SIGTERM`, `SIGKILL` at +30s,
recording the rung reached). **A timeout is a quality failure**, consistent with
ticket 05, since the likely cause is a hanging test or a runner left in watch
mode — with its own warning code, so a suite that genuinely needs longer shows
up as misconfiguration instead of a run of blamed writers.

### `out/checks.json`

A `checks-report` record — a twelfth versioned type under ticket 03, carrying a
`schema` field like the rest — holding the commit sha judged, the trigger, **the
resolved config revision the list came from**, the `setup` outcome and duration,
and per command: argv, exit code, signal if killed, wall-clock duration,
timeout and output-cap flags, and the job-relative path to captured output. Top
level `passed` is the AND of every exit code. The config revision is what makes
a job that went red under one command list and green under another, edited in
between, explainable six weeks later.

Output gets ticket 11's treatment for ticket 11's reasons: scrubbed at seal and
at every egress excerpt — test output leaks env vars constantly — and capped at
8MB per command, where hitting the cap kills the command and is itself a red
check, because a suite emitting 8MB is broken whatever it would have exited.
`checks()` returns a **tail-weighted** bounded excerpt; the failure is always at
the end.

### Guardrails

A check is not gated by ticket 05's bash allowlist — that gates a model's argv,
and gating the human's own configured command against a list the human also
configures is theatre. But **ticket 13's whole-repository ref diff wraps every
checking stage**: 13's namespace invariant is about what happened to the refs,
not about who intended it, and a `posttest` hook that tags a release breaches it
as surely as a rogue writer would. A detected movement returns the job. Checks
run under the same `.git`-write block and inherit no credentials.

### Amends four closed tickets

- [Specify the state machine and recovery protocol](02-specify-state-machine-and-recovery-protocol.md):
  the sealed-passed-evidence rule is conditional on the stage plan containing a
  `checking` stage; `setup` failure joins the infrastructure class.
- [Specify durable schemas and filesystem layout](03-specify-durable-schemas-and-filesystem-layout.md):
  a twelfth record type, `checks-report`; `NN-checking` stage directories recur
  within one job.
- [Specify the Pi work-unit protocol](05-specify-the-pi-work-unit-protocol.md):
  the resolved check command list joins the stage brief as job-level context —
  a narrow exception to "nothing else crosses a stage boundary."
- [Define verification and rollout gates](10-define-verification-and-rollout-gates.md):
  the warning-code set grows from eight to eleven — writer-green-Fleet-red,
  check timeout, and `checks: none` — all three deriving
  `reviewDepth: "elevated"`, since each means the green signal the primary would
  accept on is absent or untrustworthy.
