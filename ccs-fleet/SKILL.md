---
name: ccs-fleet
description: >-
  Deploy coding agents through the CCS CLI (`ccs <profile> -p`), each isolated in
  its own git worktree and branch, running on the local `nvidia` and `deepseek`
  profiles. Use this skill whenever the user wants work handed to another model
  rather than done here — "use ccs", "deploy/spin up agents", "delegate this",
  "farm this out", "fan these out", "run these in parallel", "get deepseek to do
  it", "send this to nemotron/nvidia/flash" — and whenever they list several
  independent chores at once, since that is the case parallel agents exist for.
  Also use it to check on, resume, review, land, or clean up agents already
  launched. Prefer this over hand-rolled `ccs` calls: raw `ccs -p` edits the
  working tree unattended, and this skill is what keeps that contained.
---

# CCS Fleet

Delegate work to other models by launching real coding agents — each one a
headless Claude Code session pointed at a non-Anthropic backend, running in a
throwaway git worktree so its edits stay quarantined until reviewed.

Everything runs through the bundled script:

```
scripts/ccs-fleet.sh
```

Use it rather than calling `ccs` directly. A bare `ccs <profile> -p "..."` runs
in whatever directory you happen to be in and **writes files with no permission
prompt** — mixed into uncommitted work, its changes become very hard to
separate from the user's. The script's whole job is to make each agent's output
land as a reviewable diff on a branch of its own.

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

Two profiles are configured. Pick by task shape, and say in one clause why:

| Task shape | Use | Why |
|---|---|---|
| Bulk, repetitive, low-stakes; wrong answers cheap to throw away | `--profile nvidia` | Nemotron 3 Ultra on OpenRouter's free tier — genuinely free, and the slow one, since free requests queue. |
| Small, well-specified mechanical edits | `--profile deepseek --model deepseek-v4-flash` | Fast and cheap; ample for edits where the brief already contains the answer's shape. |
| Large context, many files at once, genuinely hard reasoning | `--profile deepseek` | Defaults to `deepseek-v4-pro[1m]` — the 1M window lets it read broadly instead of relying on you to pre-summarize the repo. |

The free tier has a **daily request cap**, and it fails expensively: an agent
can run for minutes and many turns before dying on `429 · Rate limit exceeded:
free-models-per-day`, having changed nothing. So when a fan-out matters, do not
put every task on nvidia — and if one comes back `failed(1)`, check its `log`
for a 429 before assuming the brief was at fault. Re-routing to deepseek is the
fix; the cap resets daily.

Honour an explicit request ("use nvidia for all of these") over this table. When
fanning out several tasks, mixing profiles is good practice: it parallelizes
across two providers instead of queueing behind one rate limit.

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

$F launch --task parser-tests --profile deepseek --model deepseek-v4-flash --prompt-file /tmp/a.md
$F launch --task doc-typos    --profile nvidia                             --prompt-file /tmp/b.md
$F launch --task rename-util  --profile nvidia                             --prompt-file /tmp/c.md

$F status          # TASK / STATE / PROFILE / MODEL / files changed
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

## Reading CCS output

Two things in CCS's summary table are actively misleading, so do not pass them
on to the user:

- **`Cost`** is fabricated for these profiles — it applies Anthropic's price
  table to a model it does not recognise, and will happily report ~$0.12 for a
  one-word reply. It is not what anything cost.
- **`Model`** shows the profile default even when `--model` overrode it. The
  override does take effect; the table just does not reflect it. The truth is in
  the `[claude-code:unrecognized_model]` line in `$F log <slug>`.

`unrecognized_model` warnings and the `claude.ai connectors are disabled` notice
are both normal for third-party profiles. They are not errors.

For error codes, session mechanics, and the state layout, see
`references/mechanics.md`.
