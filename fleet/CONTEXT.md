# Fleet

The fleet moves suitable work from the primary orchestrator to lower-cost
agents while reserving the primary orchestrator for coordination and
reasoning-heavy work. The `fleet` skill and its `scripts/fleet.sh` script
manage that work from handoff through acceptance.

## Language

**Fleet**: the lower-cost agents and orchestration used to complete suitable
work outside the primary orchestrator. A fleet job may start from a ticket or
from a standalone request that must first be investigated and divided.
_Avoid_: agents, workers.

**Primary orchestrator**: the Codex or Claude session that owns coordination,
reasoning-heavy work, high-risk decisions, and final acceptance. Its token use
is the fleet's scarce resource. _Avoid_: primary agent, main agent.

**Suitable work**: work expected to consume fewer primary-orchestrator tokens
when handed to the fleet than when completed in the primary session. It may
include investigation, planning, implementation, testing, documentation, and
review. _Avoid_: cheap task, simple task.

**Reserved work**: decisions the primary orchestrator keeps because they
involve architecture, the domain model, security, irreversible operations,
breaking interfaces, production changes, or unresolved product intent. Fleet
may implement a bounded ticket after the decision is made. _Avoid_: hard task,
unsupported task.

**Delegated agent**: one headless run of the fleet's harness, pointed at a
provider model, editing inside its own worktree. It sees the repository and its
conventions, and nothing of the orchestrator's conversation. _Avoid_:
sub-agent (Pi ships no sub-agents by default), worker.

**Parent issue**: the GitHub issue that `to-tickets` divides into tracer-bullet
tickets. Fleet usually works below this level and does not own or close the
parent issue. _Avoid_: main issue.

**Ticket**: a tracer-bullet slice produced by `to-tickets`, often published as
a GitHub sub-issue with blockers and acceptance criteria. It is sized for one
fresh context window. _Avoid_: sub-issue, chore, task.

**Fleet job**: one ticket or standalone request being completed through the
fleet. Lower-cost agents may investigate and divide it into private work units,
but the primary orchestrator accepts the fleet job as a whole. _Avoid_: run,
parent issue.

**Work unit**: a private assignment to one delegated agent inside a fleet job,
such as scouting, planning, implementation, or review. A work unit is not
published to the issue tracker. _Avoid_: ticket, subtask.

**Input snapshot**: the immutable issue or request context captured for a
fleet job before delegated work begins. Fleet acquires it itself from a bare
ticket reference rather than receiving it from the primary orchestrator, so its
fidelity is verifiable. For a GitHub ticket it holds the ticket, comments,
parent issue, and blockers, and it exposes no GitHub credential to delegated
agents. It is authoritative for the whole job: never re-fetched, never patched.
_Avoid_: brief, context dump.

**Repository identity**: the stable identity of the repository a fleet job acts
on, unchanged by a rename or transfer. It is what Fleet deduplicates active
ticket jobs by, scopes repository writer capacity to, and records on routing
evidence. _Avoid_: repo path, remote URL.

**Direct path**: the fleet-job path for a ticket that already has enough
context and acceptance criteria for a writer to act. _Avoid_: simple path,
fast path.

**Discovery path**: the fleet-job path for work that first needs repository
investigation or decomposition before a writer can act. _Avoid_: planning
mode, complex path.

**Acceptance**: the primary orchestrator's determination that a fleet job as a
whole satisfies the user's objective. Delegated agents may review parts of the
job, but they do not own acceptance of the whole. Work waits in its isolated
branch until the primary orchestrator accepts and lands it. _Avoid_: review,
approval.

**Acceptance contract**: the checks and review required before work can count
as complete. The contract scales with the risk and scope of the work rather
than imposing one process on every fleet job. _Avoid_: definition of done,
quality gate.

An acceptance contract is additive: ticket criteria and repository
instructions cannot be weakened by a delegated agent. Planners and reviewers
may add checks. Fleet automatically runs only repository-defined, documented,
or explicitly allowlisted commands; external mutations stay reserved.

**Risk class**: the minimum scrutiny and starting model tier for a fleet job.
Low-risk work is mechanical or tightly bounded with deterministic checks;
medium-risk work may span files or alter behavior whose intent is already
decided; reserved work stays with the primary orchestrator. A delegated agent
may raise the initial class but never lower it. _Avoid_: difficulty, model tier.

**Brief**: the prompt that assigns a work unit to a delegated agent. Because
the harness reads the repository's own conventions, briefs can stay terse.
_Avoid_: ticket, work unit.

**Handoff**: passing a work unit to an agent so it can run without the
orchestrator's conversation, trusting the repository's CLAUDE.md/AGENTS.md to
carry its conventions. _Avoid_: delegation (delegation is the act; handoff is
the artifact and its transport).

**Escalation**: after a lower-tier agent fails a work unit, Fleet gives the
work and its failure evidence to one higher-tier agent. If that attempt also
fails, the primary orchestrator takes the work back. _Avoid_: retry loop.

**Availability escalation**: moving a work unit to a higher tier because every
candidate tried in its own tier was unavailable, not because its work was
judged inadequate. It is counted separately from escalation, so a provider
outage never consumes the job's one quality escalation. _Avoid_: escalation,
fallback.

**Failed attempt**: an agent attempt that crashes, times out, produces no
relevant change, fails its required checks, violates its scope or acceptance
criteria, or is rejected by its reviewer. A failed attempt escalates rather
than receiving an agent repair turn. _Avoid_: error (too narrow), retry.

**Infrastructure failure**: an attempt that cannot begin because its model or
provider is unavailable, unauthenticated, out of allowance, or incorrectly
configured. It consumes elapsed-time and cost budgets but not one of the two
quality attempts. Fleet tries another approved model in the tier before moving
up. _Avoid_: failed attempt, agent failure.

**Exhaustion**: the infrastructure failure of a model whose Go allowance or
direct DeepSeek wallet has run out. It is a funding condition rather than a
statement about the model, so it makes the model ineligible without counting
against its reliability or placing it in cooldown. _Avoid_: outage,
infrastructure failure (exhaustion is one kind of it).

**Model cooldown**: the temporary ineligibility of a model after consecutive
non-exhaustion infrastructure failures. It lapses on its own and never changes
a model's routing position. _Avoid_: suspension, demotion, circuit breaker.

**Ready for acceptance**: the terminal fleet-job state in which implementation,
checks, and delegated review have completed and the primary orchestrator has
received the evidence needed to accept or reject the work. _Avoid_: done.

**Returned to orchestrator**: the terminal fleet-job state in which autonomous
work has stopped because both agent tiers failed or the job requires a decision
reserved for the primary orchestrator. _Avoid_: failed, blocked.

**Oversized job**: a ticket-backed fleet job whose planner concludes the work
needs more than one writer. It is returned to the primary orchestrator with the
proposed decomposition as evidence, spending no writer attempt; Fleet neither
splits it nor publishes tickets for it. _Avoid_: too big, failed attempt.

**Job record**: the retained input, stage outputs, sessions, usage, check and
review results, and branch references for one fleet job. Cleaning working
directories does not delete this record. _Avoid_: log, report.

**Stage artifact**: a schema-validated, immutable result from one completed
orchestration stage. Fleet seals it before advancing and resumes after failure
from the last sealed stage rather than repeating paid work. _Avoid_: agent
message, transcript.

**Stage plan**: the ordered set of orchestration stages recorded at admission.
A direct job omits discovery stages. A discovery job may include read-only
scouting and planning before writing. _Avoid_: workflow, pipeline.

**Stage state**: the durable state of one planned stage. A stage is `planned`,
`active`, or `sealed`. Fleet never reruns a sealed stage. _Avoid_: job state,
attempt.

**Supervisor lease**: an expiring ownership record for a job supervisor. Its
owner and generation fence state writes, so a replacement supervisor can resume
a job after the old lease expires without allowing two supervisors to act.
_Avoid_: lock, daemon lease.

**Capacity lease**: a durable claim on a configured role limit. A writer holds
one global writer lease and one repository writer lease only while its writer
stage is active. _Avoid_: job slot, quota.

**Call intent**: the atomically recorded identity and timeout of an external
Pi call before Fleet starts it. A recovering supervisor reconciles that exact
call once and never submits a replacement paid call implicitly. _Avoid_: retry
record, request log.

**Assembly branch**: the integration branch for a standalone discovery-path
job with multiple independent writers. Fleet cherry-picks their successful
commits in the planner's declared order; conflicts enter the normal integration
escalation ladder. _Avoid_: primary branch, shared worktree.

**Job budget**: the maximum fan-out, attempts, tokens or catalog cost, and
elapsed time allowed for one fleet job. An essential work unit gets at most two
quality attempts on adjacent tiers. The initial pilot uses structural and time
limits while it gathers evidence for credible token and cost ceilings. _Avoid_:
quota, timeout.

**Model tier**: an operational routing position based on the role a model has
proven it can perform at acceptable cost: economy, standard, or premium. Output
price orders candidates for evaluation, but evidence may move a model to a
different routing position. _Avoid_: price band, quality label.

During calibration, Fleet rotates comparable work toward the least-sampled
eligible model for the same role and risk class. Rotation has no calendar
deadline: it continues until the evidence threshold is met and the user invokes
`fleet-update` to change routing.

**Economy tier**: the cheapest evaluated routing position trusted for a first
attempt on low-risk suitable work. If it does not produce acceptable work, the
work escalates immediately. _Avoid_: weak model, disposable attempt.

**Standard tier**: the normal implementation position and the first escalation
target for failed economy work. Medium-risk suitable work starts here. _Avoid_:
default model, mid-tier price band.

**Premium tier**: the allowlisted recovery position for work that fails at the
standard tier. It includes proven OpenCode Go or direct DeepSeek models; a
second delegated failure returns the work to the primary orchestrator. _Avoid_:
frontier model, unlimited retry.

**Model registry**: the routing table of approved models and their tiers,
roles, families, prices, rate bands, and context limits. Fleet ships a default
registry; a user overlay may adjust placement, eligibility, and prices, and
only `fleet-update` writes it. _Avoid_: model list, config.

**Comparable-work cohort**: the equivalence class rotation and evaluation
measure, exactly one model tier, one role, and one risk class. Repository and
language are recorded on every attempt but are not part of the cohort.
_Avoid_: bucket, sample group.

**Rate band**: the time-of-day pricing window a provider billed an attempt
under. Only direct DeepSeek has one; Fleet records the band on every attempt
and treats a peak band as a reason to prefer another eligible model. _Avoid_:
price band, tier.

**Routing evidence**: the recorded attempts, their outcomes, and the
per-cohort aggregates that `fleet-update` reads when deciding whether to move
a model's routing position. Fleet collects and reports it but never acts on it
automatically. _Avoid_: telemetry, metrics, stats.

**Clean**: remove a fleet job's worktrees and disposable build state while
retaining its job record. _Avoid_: delete, purge.

**Archive**: mark a completed job record inactive without deleting its
evidence. _Avoid_: clean, purge.

**Purge**: permanently delete one explicitly identified job record. _Avoid_:
clean, archive.

**Land**: after explicit primary-orchestrator acceptance, produce a landing
candidate — the accepted job commit or assembly branch rebased onto the
validated target tip with refreshed checks green. Fleet moves no ref outside its
own `fleet/<jobId>/` namespace, merges nothing, pushes nothing, and changes no
GitHub issue; the primary orchestrator fast-forwards or merges it. _Avoid_:
accept (acceptance is the decision; landing prepares it), merge.

**Landing candidate**: the `fleet/<jobId>/landed` branch a completed land
produces, recorded with the target sha it was fast-forwardable from. If the
target has moved past that sha, the fast-forward fails in the orchestrator's
hands rather than being resolved blind by Fleet. _Avoid_: landed branch.

**Harness**: the agent loop that turns a model plus tools into an editing
agent. The fleet's harness is **Pi**. It was previously headless Claude Code,
launched through ccs. _Avoid_: ccs (ccs is the retired launcher, not the
loop), Claude Code.

**Provider**: where a model is served and billed — opencode go (the daily
provider), DeepSeek API (premium recovery or overflow), Antigravity
(independent).
Under Pi a provider is a config entry in `~/.pi`, not a ccs "profile".
_Avoid_: profile (retired ccs term), backend.

**Worktree quarantine**: each agent edits inside its own git worktree and
branch, so its changes stay isolated and reviewable until the user lands them.
It separates ordinary Git changes but does not restrict the agent's filesystem
or network access. _Avoid_: sandbox, container, security boundary.

**Orchestration**: the lifecycle that shapes a fleet job, assigns its work,
collects evidence, escalates failures, and presents the whole job to the
primary orchestrator for acceptance. _Avoid_: management, CLI glue.

**Fleet module**: the deep module that owns orchestration policy, durable job
state, leases, model selection, worktrees, evidence, and state transitions. Its
small typed interface is shared by the CLI and MCP adapters. _Avoid_: fleet
service, fleet script.

**Fleet problem**: an expected condition that prevents a requested Fleet
operation from succeeding, returned as a typed result rather than an exception.
Examples include invalid input, policy denial, a stale confirmation, a state
conflict, a missing job, an unavailable dependency, and a capacity limit.
_Avoid_: failed attempt, infrastructure failure.

**Fleet MCP adapter**: the local stdio adapter through which Codex or Claude
submits and queries Fleet jobs using compact typed results. It does not own job
logic and is not installed into delegated Pi sessions. _Avoid_: Pi MCP, Fleet
server (too ambiguous).

**Pi adapter**: the Fleet module's process-integration adapter for delegated Pi
sessions, using Pi's supported JSONL RPC or SDK. _Avoid_: MCP (MCP faces the
primary orchestrator, not the delegated agent).

**opencode go**: the fleet's daily provider — opencode's $10/mo subscription,
billed against one model-weighted monthly allowance. _Avoid_: opencode (the
company), zen (the separate PAYG product).

**Go monthly allowance**: the shared normalized usage available to all go
models. A model's published dollar limit is what the allowance would buy if
used exclusively on that model. Spending half of one model's exclusive-use
limit leaves half of every other model's limit. _Avoid_: shared $60 cap,
per-model allowance.

**agy**: Antigravity, an independent app used for research and frontier reach.
Not part of the delivery fleet — it fails mid-delivery too often — and not
orchestrated by the fleet. _Avoid_: Antigravity CLI, backend.

**ccs**: the retired launcher that used to stand up headless Claude Code per
provider profile. Retired because per-machine setup was fragile and it dragged
Claude Code's interactive plugins and skills into headless runs where they
served nothing. Records now drive the harness directly.
