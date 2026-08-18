---
name: ccs-fleet
description: >-
  Deploy coding agents through the CCS CLI (`ccs <profile> -p`) and the
  Antigravity CLI (`agy <profile> -p`), each isolated in its own git worktree
  and branch. Backends: `nvidia`/`deepseek` (CCS, local, free-or-cheap) and
  `agy-flash`/`agy-pro`/`agy-sonnet`/`agy-opus` (Antigravity, remote and
  billed — Gemini 3.7 Flash, Gemini 3.1 Pro, Claude Sonnet 4.6, Claude Opus
  4.6). Use this skill whenever the user wants work handed to another model
  rather than done here — "use ccs", "use agy"/"antigravity", "deploy/spin up
  agents", "delegate this", "farm this out", "fan these out", "run these in
  parallel", "get deepseek to do it", "send this to nemotron/nvidia/flash/
  gemini/sonnet/opus-on-agy" — and whenever they list several independent
  chores at once, since that is the case parallel agents exist for. Also use
  it to check on, resume, review, land, or clean up agents already launched.
  Prefer this over hand-rolled `ccs`/`agy` calls: both write files unattended
  with no permission prompt, and this skill is what keeps that contained.
---

# CCS Fleet

Delegate work to other models by launching real coding agents — each one a
headless session pointed at a non-Anthropic backend, running in a throwaway
git worktree so its edits stay quarantined until reviewed. Two backends are
wired up: CCS (`nvidia`, `deepseek`, local) and Antigravity (`agy-*`, Google's
CLI, remote and billed — it's how Gemini and, at a price, Sonnet/Opus get
into the fleet).

Everything runs through the bundled script:

```
scripts/ccs-fleet.sh
```

Use it rather than calling `ccs`/`agy` directly. A bare `ccs <profile> -p
"..."` or `agy -p "..." --dangerously-skip-permissions` runs in whatever
directory you happen to be in and **writes files with no permission prompt**
— mixed into uncommitted work, its changes become very hard to separate from
the user's. The script's whole job is to make each agent's output land as a
reviewable diff on a branch of its own — it also fixes an agy-specific trap:
agy only writes into directories it already trusts, and silently redirects
anywhere else to its own scratch folder instead of erroring, so the script
always passes `--add-dir` on the worktree to grant trust for that run.

## Deciding what to delegate

Delegated agents are capable but working blind: they see the repository and its
`CLAUDE.md`, and nothing at all of the conversation you are having. That
asymmetry, not model quality, is what should drive the decision.

Good candidates are tasks where success is describable in advance — add a
function mirroring an existing one, fix typos across the docs, write tests for a
module with an established test style, mechanical renames, filling in
boilerplate. If you can state what "done" looks like in a sentence or two, an
agent can hit it.

Keep work here when the task needs judgment you cannot fully write down: architecture and design decisions, security-sensitive code,
debugging that requires forming and testing hypotheses, performance work needing
measurement, or anything governed by a project rule the agent could plausibly
violate without knowing it. When a repo's `CLAUDE.md` states a hard constraint,
delegating work that brushes against it is a bad trade — repeat the constraint
verbatim in the brief, or keep the task.

If the user asks for something in the second category anyway, say briefly why it
is a poor fit and then do as they asked; the call is theirs.

## Choosing a profile

Six profiles are configured, across two backends. Default routing is:
**reach for Antigravity first, matching the model to the task, and fall back
to deepseek when Antigravity is rate-limited or genuinely the wrong tool for
the job.** Pick by task shape, and say in one clause why:

| Task shape | Use | Why |
|---|---|---|
| Small, well-specified mechanical edits; fast turnaround wanted | `--profile agy-flash` | Gemini 3.7 Flash via Antigravity — quick and cheap, ample when the brief already contains the answer's shape. |
| Multi-file changes, moderate reasoning, still routine | `--profile agy-pro` | Gemini 3.1 Pro — a step up from Flash for tasks needing more context-juggling without paying Claude-on-agy prices. |
| Task specifically calls for Claude's judgment, and it's worth paying for | `--profile agy-sonnet` | Claude Sonnet 4.6 via Antigravity — expensive relative to the others, justified when the task shape genuinely wants Claude's style of reasoning over Gemini's. |
| Hardest reasoning, worth the highest spend | `--profile agy-opus` | Claude Opus 4.6 via Antigravity — reserve for tasks that would otherwise stay here for lack of a cheaper agent that can do them. |
| Bulk, repetitive, low-stakes; wrong answers cheap to throw away | `--profile nvidia` | Nemotron 3 Ultra on OpenRouter's free tier — genuinely free, and the slow one, since free requests queue. |
| Antigravity is rate-limited, or task needs a huge context window | `--profile deepseek` (add `--model deepseek-v4-flash` for small mechanical edits) | Defaults to `deepseek-v4-pro[1m]` — the 1M window handles large-context tasks Antigravity's models aren't suited for either. |

Antigravity is billed per token and Sonnet/Opus on it cost noticeably more
than the Gemini tiers — worth it when the task shape specifically calls for
Claude's reasoning, wasteful for something Flash would nail. Do not reach for
`agy-sonnet`/`agy-opus` by default; use them when the task is hard enough that
a cheaper agent would plausibly get it wrong, or the user says to.

Both backends fail expensively under rate limits — an agent can run for
minutes before dying having changed nothing. nvidia's free tier has a daily
cap (`429 · Rate limit exceeded: free-models-per-day`); Antigravity can hit
its own quota or billing limits (check `log <slug>` for a `429` or a quota/
billing message in the JSON `error` field). Either way, re-route rather than
retry blind: nvidia → deepseek, and any `agy-*` profile → `deepseek` (its 1M
context covers most of what the Antigravity tier would have handled). If a
`agy-*` run comes back `failed(1)`, read its `log` for the reason before
assuming the brief was at fault — it may be a quota, not a mistake.

Honour an explicit request ("use nvidia for all of these", "keep this off
agy") over this table. When fanning out several tasks, mixing profiles is
good practice: it parallelizes across backends instead of queueing behind one
rate limit, and keeps a quota hit on one backend from stalling the whole
fan-out.

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

scripts/ccs-fleet.sh launch --task parser-tests \
  --profile deepseek --model deepseek-v4-flash \
  --prompt-file /tmp/brief-parser-tests.md
```

## Running a fleet

`launch` returns immediately — the agent is detached and survives the command
that started it, so launching several in a row *is* the parallelism. Give each a
distinct slug.

```bash
F=~/.claude/skills/ccs-fleet/scripts/ccs-fleet.sh

$F launch --task parser-tests  --profile agy-flash  --prompt-file /tmp/a.md
$F launch --task doc-typos     --profile agy-flash  --prompt-file /tmp/b.md
$F launch --task hard-refactor --profile agy-sonnet --prompt-file /tmp/c.md

$F status          # TASK / STATE / TOOL / PROFILE / MODEL / files changed
```

Poll `status` rather than blocking; agents typically take from tens of seconds
to a few minutes. States are `running`, `done`, `failed(N)`, `timeout` (the
30-minute cap, tunable with `CCS_FLEET_TIMEOUT`), or `died` (killed before it
could record an exit code).

Only fan out tasks that are genuinely independent. Two agents editing the same
file will each succeed in their own worktree and then collide at merge — if
tasks share a file, run them in sequence, or give one agent both.

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
the process ended, not that the task was done. `status` counts every file the agent
touched since it started, so `0 file(s)` on a `done` agent means it changed
nothing at all — a result worth reporting rather than quietly relaunching.

`land` refuses to merge while the user's own working tree is dirty, because a
merge conflict tangled with uncommitted work is a genuinely unpleasant thing to
unpick. Commit or stash first.

It also prints the exact file list it is committing, and filters out ephemeral
build artifacts — `__pycache__`, `.pytest_cache`, `.coverage`, `node_modules`
and friends — which would otherwise be swept in by `git add -A` in any repo
without a `.gitignore` covering them. Skipped paths are always named rather than
silently dropped, so if a filter is wrong you can see it and correct it (add the
path to the repo's `.gitignore`, or point `CCS_FLEET_EXCLUDES_FILE` at your own
pattern file). An agent that produced nothing but artifacts makes `land` refuse
rather than create an empty commit — worth reading its `log` when that happens,
because it usually means the agent never did the work.

Each agent commits its own work to its branch as it finishes, so `git diff
main..ccs/<slug>` is a real record and `land` is just the merge. `clean` still
deletes the branch, so clean up only what you have reviewed.

If an agent got close but missed, `resume` continues that same session in the
same worktree, with everything it already knows still loaded:

```bash
$F resume <slug> --prompt "You edited src/config.py; the brief said not to. Revert that file and leave the test changes."
```

That is usually a better move than relaunching, and it is cheaper. Reach for a
fresh launch when the brief itself was the problem.

Clean up landed and abandoned agents once done — stale worktrees accumulate and
`git worktree list` gets noisy.

## Reading CCS and agy output

CCS's and agy's `log <slug>` output look nothing alike, and each has its own
trap.

For **CCS** profiles (`nvidia`, `deepseek`), two things in its summary table
are actively misleading, so do not pass them on to the user:

- **`Cost`** is fabricated for these profiles — it applies Anthropic's price
  table to a model it does not recognise, and will happily report ~$0.12 for a
  one-word reply. It is not what anything cost.
- **`Model`** shows the profile default even when `--model` overrode it. The
  override does take effect; the table just does not reflect it. The truth is in
  the `[claude-code:unrecognized_model]` line in `$F log <slug>`.

`unrecognized_model` warnings and the `claude.ai connectors are disabled` notice
are both normal for third-party profiles. They are not errors.

For **agy** profiles (`agy-*`), `log <slug>` is a single JSON object —
`{"conversation_id", "status", "response", "duration_seconds", "usage", ...}`.
This is more trustworthy than CCS's table: `status` is `"SUCCESS"` or
`"ERROR"` and lines up with the process exit code, `usage` is real token
counts, and there's no fabricated cost figure to filter out. If `status` is
`"ERROR"`, the `error` field states the reason directly (bad model name,
quota/billing limit, etc.) — read it before re-routing or relaunching.

For error codes, session mechanics, and the state layout, see
`references/mechanics.md`.
