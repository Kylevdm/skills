---
name: fleet
description: >-
  Deploy coding agents through the Pi CLI (`pi`, pi.dev), each isolated in
  its own git worktree and branch, running against opencode's `go`
  subscription. Profiles: `pi-default` (MiniMax M3, the everyday reach),
  `pi-plus` (Qwen3.7 Plus, a second opinion from a different model family),
  and `pi-deepseek` (DeepSeek V4 Pro — explicit request only, not a
  default). Use this whenever the user wants work handed to another model
  rather than done here — "use pi", "use opencode/zen/go", "deploy/spin up
  agents", "delegate this", "farm this out", "fan these out", "run these in
  parallel", "get minimax/qwen/deepseek to do it" — and whenever they list
  several independent chores at once, since that is the case parallel
  agents exist for. Also use it to check on, resume, review, land, or clean
  up agents already launched. Prefer this over a hand-rolled `pi` call: it
  writes files unattended with no permission prompt, and this skill is what
  keeps that contained. Antigravity (`agy`) is a separate, independent app
  and out of scope for this skill.
---

# Fleet

Delegate work to other models by launching real coding agents — each one a
headless Pi session pointed at opencode's `go` subscription, running in a
throwaway git worktree so its edits stay quarantined until reviewed. Every
brief is framed as an `/implement` run (seams -> TDD -> typecheck -> full
suite -> commit), per the mattpocock `implement` skill, with the review beat
carved out and kept local: the delegated agent never reviews its own diff,
you do, before `land`.

One backend for now: **opencode go**, the $10/mo subscription, billed against
a shared **$60 monthly usage cap** across every model in it (see
`fleet/CONTEXT.md` and `docs/adr/0002-go-shared-cap-routing.md`). Antigravity
(`agy`) is a separate app the user runs independently — it is not
orchestrated by this skill and not a fallback path here (see
`docs/adr/0001-adopt-pi-as-the-fleet-harness.md` for why).

Everything runs through the bundled script:

```
scripts/fleet.sh
```

Use it rather than calling `pi` directly. A bare `pi -p "..."` runs in
whatever directory you happen to be in and **writes files with no permission
prompt** — Pi has no built-in permission system, it just acts with the
launching user's own filesystem access — so mixed into uncommitted work, its
changes become very hard to separate from the user's. The script's job is to
make each agent's output land as a reviewable diff on a branch of its own. It
also probes the profile before launching, so a misconfigured key or a dead
model id dies in a second with the provider's own error instead of running
an agent against a backend that was never going to answer.

## The go profiles route code to China-hosted inference

All three profiles run on models served from China — reaching them required
enabling opencode's China-hosting opt-in on the workspace. Hosting location
itself is not the concern: the user is fine with Chinese-hosted inference.
The actual constraint is data retention/training — a model that trains on
submitted code is not acceptable, and models known to do that are excluded
at the opencode workspace/account level before they ever reach this skill's
routing table, not by a routing rule here. If a new profile is ever added,
confirm its training/retention terms before wiring it in; this is meant to
be a standing check whenever `fleet-update` changes the profile table (that
skill itself still needs a Pi-era rewrite before it can carry this check —
see the fog ledger).

## Deciding what to delegate

Delegated agents are capable but working blind: they see the repository and
its `CLAUDE.md`/`AGENTS.md`, and nothing at all of the conversation you are
having. That asymmetry, not model quality, is what should drive the
decision.

Good candidates are tasks where success is describable in advance — add a
function mirroring an existing one, fix typos across the docs, write tests
for a module with an established test style, mechanical renames, filling in
boilerplate. If you can state what "done" looks like in a sentence or two, an
agent can hit it.

Keep work here when the task needs judgment you cannot fully write down:
architecture and design decisions, security-sensitive code, debugging that
requires forming and testing hypotheses, performance work needing
measurement, or anything governed by a project rule the agent could
plausibly violate without knowing it. When a repo's `CLAUDE.md`/`AGENTS.md`
states a hard constraint, delegating work that brushes against it is a bad
trade — repeat the constraint verbatim in the brief, or keep the task.

If the user asks for something in the second category anyway, say briefly why
it is a poor fit and then do as they asked; the call is theirs.

## Choosing a profile

Work down this list and stop at the first line that fits. Say in one clause
why.

1. **Default coding work, including multi-file changes** →
   `--profile pi-default` (MiniMax M3). The fleet's normal reach until an
   evaluation run says otherwise — see the note below.
2. **A second opinion from a different model family, or `pi-default` missed** →
   `--profile pi-plus` (Qwen3.7 Plus). Same endpoint, same cap pool, useful
   when a task wants a different model's read rather than a retry.
3. **The user explicitly asks for DeepSeek** → `--profile pi-deepseek`
   (DeepSeek V4 Pro). Not a default: per
   `docs/adr/0002-go-shared-cap-routing.md`, it is the fleet's former default
   and best-validated model, kept available for explicit requests while the
   rest of the pool gets evaluated on its own merits.
4. **Not worth the overhead of orchestrating** → do it here yourself. A
   one-line fix costs more to brief, poll, and review than to make.

`pi-default`/`pi-plus` are **provisional**, not evidence-backed yet: nothing
in this pool has been graded against a hidden test suite the way
`deepseek-v4-pro` was under the old ccs fleet. Treat a `done` result from
either with a closer read than you would a validated default, and note
surprises (wrong-target edits, missed instructions, needing `resume`) so the
routing table can be corrected. See `docs/adr/0002-go-shared-cap-routing.md`
for the evaluation plan.

Honour an explicit request ("use deepseek for this", "try qwen instead") over
this list. When fanning out several tasks, mixing profiles is good practice —
it spreads the shared $60 cap's burn across models instead of one model
eating it alone. Only fan out genuinely independent tasks — two agents
editing the same file will each succeed in their own worktree and then
collide at merge, so if tasks share a file, run them in sequence or give one
agent both.

When something fails, read `log <slug>` before re-routing: a `429` or a quota
message is a limit, not a bad brief — the whole $60 cap is shared, so any
model can trip it. `$F verify` names the provider's own error.

## Writing the brief

This is where delegation succeeds or fails. The agent has the repo and
nothing else — no memory of what the user just told you, no idea which file
you were looking at. A brief that reads fine to someone following your
conversation can be unfollowable to an agent starting cold.

A brief worth sending states, concretely:

- **Where** — actual paths, not "the parser".
- **What** — the change, in terms of observable outcome.
- **The pattern to follow** — name the existing function, test, or file to
  imitate. This is the cheapest quality lever available; models match a shown
  pattern far more reliably than a described one.
- **How to check** — the test command, or what the output should look like.
- **The boundary** — what to leave alone. Agents left unbounded reformat
  neighbouring code and inflate the diff you have to review.

Underneath those five, every brief carries the same fixed harness, borrowed
from the mattpocock `implement` skill — don't re-derive it per task, just
apply it:

1. Work out the seams from the brief before writing code.
2. Drive TDD at those seams — red, then green, one slice at a time.
3. Typecheck as it goes; run single test files along the way.
4. Run the full test suite once, at the end.
5. Commit to the branch (the worktree setup means this is always safe — it's
   isolated from your own tree). Pi never commits on its own initiative; say
   so explicitly and it will run `git commit` itself via its bash tool.

Do not ask the agent to "just write the code" — ask for these five beats
explicitly, the same way you'd invoke `/implement` yourself. And do not ask
it to review its own work, run `/code-review`, or judge whether it's done:
that step is deliberately never delegated — you do it, on `$F diff <slug>`,
before `land` (see Reviewing and landing below). A model grading its own diff
tends to miss what it got wrong.

Use `--prompt-file` for anything beyond a sentence. It sidesteps shell
quoting entirely, and long briefs are exactly where quoting breaks.

```bash
cat > /tmp/brief-parser-tests.md <<'BRIEF'
Add unit tests for `parse_config()` in src/config.py.

Put them in tests/test_config.py, matching the structure and naming of the
existing tests in tests/test_loader.py — same fixtures, same assert style.

Cover: a valid config, a missing required key, and a malformed YAML file.

Work test-first: write one failing test, make it pass, repeat per case.
Typecheck and run tests/test_config.py as you go; run the full suite once at
the end. Commit your work to this branch (run `git commit`) when done.

Verify with: pytest tests/test_config.py

Do not modify src/config.py itself, and do not touch any other test file.
Do not review your own work or run code-review — just commit when the suite
is green.
BRIEF

scripts/fleet.sh launch --task parser-tests \
  --profile pi-default --prompt-file /tmp/brief-parser-tests.md
```

## Running a fleet

`launch` returns immediately — the agent is detached and survives the
command that started it, so launching several in a row *is* the
parallelism. Give each a distinct slug.

```bash
F=~/.claude/skills/fleet/scripts/fleet.sh

$F launch --task parser-tests  --profile pi-default --prompt-file /tmp/a.md
$F launch --task doc-typos     --profile pi-default --prompt-file /tmp/b.md
$F launch --task hard-refactor --profile pi-plus     --prompt-file /tmp/c.md

$F status          # TASK / STATE / PROFILE / MODEL / files changed
```

Poll `status` rather than blocking; agents typically take from tens of
seconds to a few minutes. States are `running`, `done`, `failed(N)`,
`timeout` (the 30-minute cap, tunable with `PI_FLEET_TIMEOUT`), or `died`
(killed before it could record an exit code).

## Reviewing and landing

```bash
$F diff <slug>     # everything the agent changed, against the commit it started from
$F log  <slug>     # raw pi output — the agent's own account of what it did
$F land <slug>     # commit its work and merge the branch into your current HEAD
$F clean <slug>    # remove worktree, branch, and run state
```

Read the diff before landing, every time, and tell the user what the agent
actually did rather than repeating its self-report — agents routinely claim
success while having edited the wrong thing, and an exit code of 0 only means
the process ended, not that the task was done. `status` counts every file
the agent touched since it started, so `0 file(s)` on a `done` agent means it
changed nothing at all — a result worth reporting rather than quietly
relaunching.

This is beat 6 of the Implementation Framework, and it is yours alone: run
`/code-review` against `$F diff <slug>` before `land`, the same way
`implement` runs code-review before its own commit. The delegated agent was
never asked to review itself, so nothing has checked this diff yet except
you. Act on what it finds — fix small things directly in the worktree before
landing, or `resume` the agent with the specific findings for anything
substantial. Only call the task done once your review has passed.

`land` refuses to merge into a dirty working tree — commit or stash first. It
prints the file list it is committing and filters ephemeral build artifacts
(`__pycache__`, `node_modules` and friends), always naming what it skipped
rather than dropping it silently; override with `PI_FLEET_EXCLUDES_FILE`.

If the agent committed its own work as instructed, `git diff main..pi/<slug>`
is a real record and `land` is just the merge; if it left changes
uncommitted, `land`'s own `stage_and_commit` step covers that too. `clean`
deletes the branch, so clean up only what you have reviewed.

If an agent got close but missed, `resume` continues the same slug's session
in the same worktree:

```bash
$F resume <slug> --prompt "You edited src/config.py; the brief said not to. Revert that file and leave the test changes."
```

That is usually a better move than relaunching, and it is cheaper. Reach for
a fresh launch when the brief itself was the problem. **Resume's session
continuity is not yet proven** — the fleet stores each agent's session under
its own state directory and passes the same handle back on resume, but
whether Pi actually recalls prior turns from that hasn't been verified end
to end. Treat a resumed agent's "I remember" claims with the same skepticism
as any other self-report until this is checked.

## When a profile stops working

```bash
$F verify              # probe every profile; or: $F verify pi-default
```

Each profile gets a real 24-token completion against opencode go and reports
the provider's own error. This is the first thing to run when a launch is
refused or an agent fails oddly. The launch preflight uses the same probe, so
a dead profile costs about a second and names its own cause — an
authentication error means the key in `~/.pi/agent/auth.json` is stale (fix
with `pi login`), a credits/region error names its own fix directly. Pass
`--no-preflight` to skip it.

## Reading Pi output

`log <slug>` is Pi's own print-mode transcript — plain prose describing what
it did, ending in its own summary, the way our smoke-test run closed with
"Done. - Created `fleet/SMOKE_TEST.md` ... - Committed it on branch
`pi/smoke1`". There is no fabricated cost figure the way ccs's summary table
used to produce one (~$0.21 for a one-word reply from a free model, applying
Anthropic's price table to a model it didn't recognise) — Pi simply doesn't
print one in this mode. Don't over-trust the prose either: it is the agent's
self-report, and `$F diff <slug>` is the ground truth.

For error codes, session mechanics, endpoint details, and the state layout,
see `references/mechanics.md`.
