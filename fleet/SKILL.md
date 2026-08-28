---
name: fleet
description: >-
  Deploy coding agents through the CCS CLI (`ccs <profile> -p`) and the
  Antigravity CLI (`agy <profile> -p`), each isolated in its own git worktree
  and branch. Profiles: `oc-smart`/`oc-fast` (opencode Zen go subscription —
  DeepSeek V4 Pro and Flash), `oc-free` (free-tier, throwaway work only),
  `deepseek` (DeepSeek's own API, the overflow once the subscription's
  monthly cap is hit), and `agy-gemini`/`agy-opus` (Antigravity — Gemini 3.1
  Pro for research, Claude Opus 4.6 as the frontier escape hatch, on a
  tighter quota). Use this skill whenever the user wants work handed to
  another model rather than done here — "use ccs", "use agy"/"antigravity",
  "use opencode/zen", "deploy/spin up agents", "delegate this", "farm this
  out", "fan these out", "run these in parallel", "get
  deepseek/gemini/opus to do it" — and whenever they list several
  independent chores at once, since that is the case parallel agents exist
  for. Also use it to check on, resume, review, land, or clean
  up agents already launched. Prefer this over hand-rolled `ccs`/`agy` calls:
  both write files unattended with no permission prompt, and this skill is
  what keeps that contained.
---

# CCS Fleet

Delegate work to other models by launching real coding agents — each one a
headless session pointed at a non-Anthropic backend, running in a throwaway
git worktree so its edits stay quarantined until reviewed.

Two backends. **CCS** carries the everyday fleet: `oc-*` on the opencode Zen
`go` subscription (flat $10/mo against a $60 monthly usage cap) and
`deepseek` on DeepSeek's own pay-as-you-go API. **Antigravity** (`agy-*`) is
the frontier reach — Gemini and Claude, on a tighter quota, and optional: if
`agy` isn't installed those two profiles are simply unavailable and the work
stays here.

Everything runs through the bundled script:

```
scripts/fleet.sh
```

Use it rather than calling `ccs`/`agy` directly. A bare `ccs <profile> -p
"..."` or `agy -p "..." --dangerously-skip-permissions` runs in whatever
directory you happen to be in and **writes files with no permission prompt** —
mixed into uncommitted work, its changes become very hard to separate from the
user's. The script's job is to make each agent's output land as a reviewable
diff on a branch of its own. It also probes the profile before launching, so a
misconfigured backend dies in a second with the provider's own error instead of
hanging for two minutes, and passes agy the `--add-dir` it needs to write into
a worktree at all.

## The `oc-*` profiles route code to China-hosted inference

`oc-fast`, `oc-smart`, and `oc-free` all run on models served from China —
reaching them required enabling opencode's China-hosting opt-in on the
workspace. That is a data-residency question, not a performance one. Raise it
before sending client code, proprietary source, or anything under a
contractual hosting constraint through them; `agy-*` and the orchestrator are
the alternatives.

## Deciding what to delegate

Delegated agents are capable but working blind: they see the repository and its
`CLAUDE.md`, and nothing at all of the conversation you are having. That
asymmetry, not model quality, is what should drive the decision.

Good candidates are tasks where success is describable in advance — add a
function mirroring an existing one, fix typos across the docs, write tests for a
module with an established test style, mechanical renames, filling in
boilerplate. If you can state what "done" looks like in a sentence or two, an
agent can hit it.

Keep work here when the task needs judgment you cannot fully write down:
architecture and design decisions, security-sensitive code, debugging that
requires forming and testing hypotheses, performance work needing measurement,
or anything governed by a project rule the agent could plausibly violate
without knowing it. When a repo's `CLAUDE.md` states a hard constraint,
delegating work that brushes against it is a bad trade — repeat the constraint
verbatim in the brief, or keep the task.

If the user asks for something in the second category anyway, say briefly why it
is a poor fit and then do as they asked; the call is theirs.

## Choosing a profile

Work down this list and stop at the first line that fits. Say in one clause why.

1. **Default coding work, including hard multi-file refactors** →
   `--profile oc-smart` (DeepSeek V4 Pro). The fleet's normal reach, and
   stronger than "default" suggests: everything else on this list is a reason
   to deviate, and difficulty alone is not one of them.
2. **Small, well-specified mechanical edits, fast turnaround** →
   `--profile oc-fast` (DeepSeek V4 Flash). Same endpoint, ~3× cheaper against
   the cap, ample when the brief already contains the answer's shape.
3. **The subscription's $60 monthly cap is exhausted** → `--profile deepseek`.
   DeepSeek's own pay-as-you-go API, which bills separately. It is the overflow
   path, not an upgrade — same model family as `oc-smart`.
4. **The task genuinely needs Claude's judgment and is worth the tighter
   quota** → `--profile agy-opus` (Claude Opus 4.6). The escape hatch for work
   that would otherwise stay here for lack of an agent that can do it, and the
   only escalation above `oc-smart` — so escalate on task *kind*, not on a
   hunch that something is difficult.
5. **Research rather than coding** — reading docs, surveying approaches,
   answering an open question → `--profile agy-gemini` (Gemini 3.1 Pro).
6. **Not worth the overhead of orchestrating, or `agy` is absent and the task
   needed it** → do it here yourself. A one-line fix costs more to brief,
   poll, and review than to make.
7. **Playing, throwaway, or genuinely disposable output** → `--profile
   oc-free`. Free-tier models: the id rots constantly, quality is low, and
   **free-tier requests may be logged and used for training**. Never send real
   work, proprietary code, or anything confidential through it.

There is deliberately no tier between `oc-smart` and `agy-opus`. A Qwen 3.8
Max tier was built and then removed: on a hard nested-config refactor both it
and `oc-smart` scored 16/16 against a hidden test suite, but Qwen took 1.9×
as long and wrote 45% more code. `--model qwen3.8-max` on `oc-smart` is still
there if a task ever wants a second opinion from a different model family.

Honour an explicit request ("use deepseek for all of these", "keep this off
agy") over this list. When fanning out several tasks, mixing profiles is good
practice: it parallelizes across backends instead of queueing behind one rate
limit. Only fan out genuinely independent tasks — two agents editing the same
file will each succeed in their own worktree and then collide at merge, so if
tasks share a file, run them in sequence or give one agent both.

When something fails, read `log <slug>` before re-routing: a `429` or a quota
message is a limit, not a bad brief. `agy-*` hitting its quota falls back to
`oc-smart`; `oc-*` returning `CreditsError` means the subscription cap is gone
and `deepseek` is the overflow.

## Writing the brief

This is where delegation succeeds or fails. The agent has the repo and nothing
else — no memory of what the user just told you, no idea which file you were
looking at. A brief that reads fine to someone following your conversation can
be unfollowable to an agent starting cold.

A brief worth sending states, concretely:

- **Where** — actual paths, not "the parser".
- **What** — the change, in terms of observable outcome.
- **The pattern to follow** — name the existing function, test, or file to
  imitate. This is the cheapest quality lever available; models match a shown
  pattern far more reliably than a described one.
- **How to check** — the test command, or what the output should look like.
- **The boundary** — what to leave alone. Agents left unbounded reformat
  neighbouring code and inflate the diff you have to review.

Use `--prompt-file` for anything beyond a sentence. It sidesteps shell quoting
entirely, and long briefs are exactly where quoting breaks.

```bash
cat > /tmp/brief-parser-tests.md <<'BRIEF'
Add unit tests for `parse_config()` in src/config.py.

Put them in tests/test_config.py, matching the structure and naming of the
existing tests in tests/test_loader.py — same fixtures, same assert style.

Cover: a valid config, a missing required key, and a malformed YAML file.

Verify with: pytest tests/test_config.py

Do not modify src/config.py itself, and do not touch any other test file.
BRIEF

scripts/fleet.sh launch --task parser-tests \
  --profile oc-fast --prompt-file /tmp/brief-parser-tests.md
```

## Running a fleet

`launch` returns immediately — the agent is detached and survives the command
that started it, so launching several in a row *is* the parallelism. Give each a
distinct slug.

```bash
F=~/.claude/skills/fleet/scripts/fleet.sh

$F launch --task parser-tests  --profile oc-fast  --prompt-file /tmp/a.md
$F launch --task doc-typos     --profile oc-fast  --prompt-file /tmp/b.md
$F launch --task hard-refactor --profile oc-smart --prompt-file /tmp/c.md

$F status          # TASK / STATE / TOOL / PROFILE / MODEL / files changed
```

Poll `status` rather than blocking; agents typically take from tens of seconds
to a few minutes. States are `running`, `done`, `failed(N)`, `timeout` (the
30-minute cap, tunable with `CCS_FLEET_TIMEOUT`), or `died` (killed before it
could record an exit code).

## Reviewing and landing

```bash
$F diff <slug>     # everything the agent changed, against the commit it started from
$F log  <slug>     # raw CCS output — the agent's own account of what it did
$F land <slug>     # commit its work and merge the branch into your current HEAD
$F clean <slug>    # remove worktree, branch, and run state
```

Read the diff before landing, every time, and tell the user what the agent
actually did rather than repeating its self-report — agents routinely claim
success while having edited the wrong thing, and an exit code of 0 only means
the process ended, not that the task was done. `status` counts every file the
agent touched since it started, so `0 file(s)` on a `done` agent means it
changed nothing at all — a result worth reporting rather than quietly
relaunching.

`land` refuses to merge into a dirty working tree — commit or stash first. It
prints the file list it is committing and filters ephemeral build artifacts
(`__pycache__`, `node_modules` and friends), always naming what it skipped
rather than dropping it silently; override with `CCS_FLEET_EXCLUDES_FILE`.

Each agent commits its own work to its branch as it finishes, so `git diff
main..ccs/<slug>` is a real record and `land` is just the merge. `clean`
deletes the branch, so clean up only what you have reviewed.

If an agent got close but missed, `resume` continues that same session in the
same worktree, with everything it already knows still loaded:

```bash
$F resume <slug> --prompt "You edited src/config.py; the brief said not to. Revert that file and leave the test changes."
```

That is usually a better move than relaunching, and it is cheaper. Reach for a
fresh launch when the brief itself was the problem.

## When a profile stops working

```bash
$F verify              # probe every profile; or: $F verify oc-smart
```

Each profile gets a real 24-token completion and reports the provider's own
error, plus any drift between the live config and what the fleet expects. This
is the first thing to run when a launch is refused or an agent fails oddly —
it is also what catches `oc-free`'s model id rotting away, which happens often.
`--model <another-free-id>` works around that for one run.

The launch preflight uses the same probe, so a dead profile costs about a
second and names its own cause: `CreditsError: Insufficient balance` means the
`go` cap is exhausted (route to `deepseek`), `RegionError` means the workspace
opt-in lapsed, `ModelError: not supported` means the id is wrong for that
endpoint. Pass `--no-preflight` to skip it.

## Reading CCS and agy output

For **CCS** profiles (`oc-*` and `deepseek`), two things in the summary table
are actively misleading, so do not pass them on to the user:

- **`Cost`** is fabricated — it applies Anthropic's price table to a model it
  does not recognise. It will report ~$0.21 for a one-word reply from a *free*
  model. It is not what anything cost.
- **`Model`** shows the profile default even when `--model` overrode it. The
  override does take effect; the table just does not reflect it. The truth is
  in the `[claude-code:unrecognized_model]` line in `$F log <slug>`.

`unrecognized_model` warnings and the `claude.ai connectors are disabled`
notice are both normal for third-party profiles. They are not errors.

For **agy** profiles, `log <slug>` is a single JSON object — `{"conversation_id",
"status", "response", "duration_seconds", "usage", ...}`. This is more
trustworthy than CCS's table: `status` is `"SUCCESS"` or `"ERROR"` and lines up
with the process exit code, `usage` is real token counts, and there is no
fabricated cost figure. If `status` is `"ERROR"`, the `error` field states the
reason directly — read it before re-routing or relaunching.

For error codes, session mechanics, endpoint details, and the state layout, see
`references/mechanics.md`.
