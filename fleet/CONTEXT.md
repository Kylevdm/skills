# Fleet

The fleet is the pool of delegated coding agents the user launches to implement
**defined tickets** on other models, each isolated in a throwaway git worktree
until its diff is reviewed and landed. The `fleet` skill and its
`scripts/fleet.sh` script are the orchestration for that pool.

## Language

**Fleet**: the pool of coding agents available to take a defined ticket and
return a reviewable diff on a branch of its own. _Avoid_: agents, workers.

**Delegated agent**: one headless run of the fleet's harness, pointed at a
provider model, editing inside its own worktree. It sees the repository and its
conventions, and nothing of the orchestrator's conversation. _Avoid_:
sub-agent (Pi ships no sub-agents by default), worker.

**Defined ticket**: a task whose "done" is describable in advance — concrete
paths, a pattern to imitate, a way to check. The only class of work the fleet
exists for; work needing judgment the orchestrator cannot write down stays with
the orchestrator. _Avoid_: chore, task (too generic).

**Brief**: the prompt sent to an agent — the defined ticket plus the process
beats it must follow. Because the harness reads the repo's own conventions,
briefs can stay terse. _Avoid_: ticket (the ticket is the task; the brief is
what is sent).

**Handoff**: passing a defined ticket to an agent so it can run without the
orchestrator's conversation, trusting the repo's CLAUDE.md/AGENTS.md to carry
the conventions. _Avoid_: delegation (delegation is the act; handoff is the
artifact and its transport).

**Harness**: the agent loop that turns a model plus tools into an editing
agent. The fleet's harness is **Pi**. It was previously headless Claude Code,
launched through ccs. _Avoid_: ccs (ccs is the retired launcher, not the
loop), Claude Code.

**Provider**: where a model is served and billed — opencode go (the daily
provider), DeepSeek API (overflow / explicit use), Antigravity (independent).
Under Pi a provider is a config entry in `~/.pi`, not a ccs "profile".
_Avoid_: profile (retired ccs term), backend.

**Worktree quarantine**: each agent edits inside its own git worktree and
branch, so its changes stay isolated and reviewable until the user lands them.
This, not the harness, is what makes an unattended agent safe to run.
_Avoid_: sandbox, container.

**Orchestration**: the launch → status → diff → review → land → clean
lifecycle the fleet script wraps around a harness run. The review beat is the
user's alone and is never delegated. _Avoid_: management, CLI glue.

**opencode go**: the fleet's daily provider — opencode's $10/mo subscription,
billed against a shared **$60 monthly usage cap** at each model's list price.
_Avoid_: opencode (the company), zen (the separate PAYG product).

**Shared $60 cap**: the single monthly usage allowance shared by all go
models; a model's list price decides how fast the cap burns, so cheap models
stretch the month and burn-rate is a routing input, not an afterthought.
_Avoid_: quota, allowance (each model's listed $60 is the shared pot, not a
per-model one).

**agy**: Antigravity, an independent app used for research and frontier reach.
Not part of the delivery fleet — it fails mid-delivery too often — and not
orchestrated by the fleet. _Avoid_: Antigravity CLI, backend.

**ccs**: the retired launcher that used to stand up headless Claude Code per
provider profile. Retired because per-machine setup was fragile and it dragged
Claude Code's interactive plugins and skills into headless runs where they
served nothing. Records now drive the harness directly.
