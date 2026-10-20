---
name: pi-delegate
description: Delegate coding work to cheaper models through pi inside pi-jail, while Claude stays the orchestrator that plans, briefs, reviews every diff, runs the gates and commits. Use when the user says "delegate #N", "send #N to pi", "delegate to gpt/glm/kimi", "bake off #N", "delegate spec #N" or a whole map's tickets, "pi-jail", "hold the PR", or asks to hand an issue, fix, test-writing job or second-opinion review to another model to save Claude usage. Also use when deciding unprompted whether a task should be delegated or done directly.
---

# pi delegation

`pi` (`~/.local/bin/pi`) is a multi-model coding agent over the user's ChatGPT Plus, OpenCode Go and
DeepSeek accounts. You orchestrate: plan, brief, review every diff, run the gates, commit and open
PRs. Delegation exists to save Claude usage **without lowering quality**, so the review half is
never delegated away; a model grading its own work misses its own mistakes.

Do the work yourself when briefing costs about as much as doing it, when it needs this
conversation's context, or when it is security-critical.

## What the user says

| User says | You do |
|---|---|
| "delegate #N" / "send #N to pi" | Full route below, model from the roster |
| "delegate #N to gpt / glm / kimi" | Same, with that model |
| "bake off #N" | Several models on the same brief in parallel; compare side by side |
| "delegate spec #N" / "delegate the map" / a list of tickets | Batch route: [references/batch.md](references/batch.md) |
| "do #N yourself" | No delegation |
| "…, hold the PR" | Stop after review; the user approves before commit/PR |
| nothing | Decide per task and say which route you picked and why |

## Roster

| Work | Model |
|---|---|
| General fixes (default) | `opencode-go/glm-5.2` |
| Larger multi-file or design-heavy work; second-opinion reviews | `openai/gpt-6.1-sol` (ChatGPT Plus quota) |
| Mechanical edits, writing tests, lint/type fix-ups | `opencode-go/kimi-k2.7-code` |
| Cheap, fast, large-context sweeps; extra reviewer when allowance is tight | `opencode-go/deepseek-v4.1-flash` |
| Throwaway prototypes | `opencode-go/longcat-2.5-preview-free` |

- When reviewing gpt-6.1-sol's own output, use glm-5.2, so it isn't grading itself.
- **Never** `openai/gpt-6-sol`. **Never** direct `deepseek/*` (paid credits; OpenCode Go serves the
  same models).
- **Avoid unless asked:** any Go model with a $15 monthly limit (see
  [assets/go-limits.tsv](assets/go-limits.tsv)): Kimi K3, Grok 4.7, Qwen3.8 Max, GLM-5.3, DeepSeek V4
  Pro, MiMo Pro, Claude Haiku. They use the allowance four times faster than a $60 model. The luna
  models are also on ChatGPT Plus, so use them only as `openai/gpt-6-luna` / `openai/gpt-5.6-luna`.
  `scripts/run.sh` refuses all of these; `PI_DELEGATE_ALLOW_LOW_LIMIT=1` overrides when the user asked.
- ChatGPT Plus accepts gpt-6.1-sol, gpt-6-astra, gpt-6-luna, gpt-5.6-sol, gpt-5.6-terra and
  gpt-5.6-luna (checked 2026-10-20); gpt-5.5, gpt-5.3-codex and gpt-5.4-mini return 400. Plus caps per
  model aren't published: use it freely and back off on a rate-limit error.
- pi's default model is `opencode-go/kimi-k2.7-code`, so a forgotten `--model` costs little, but pass
  it every time anyway.

### The Go allowance

OpenCode Go is **one summed allowance**: each run uses spend ÷ that model's monthly limit, and the
fractions of all models add up against the 5-hour (20%), weekly (50%) and monthly (100%) windows.
$11 of glm-5.2 is 11/60 = 18% of the month, and nearly a whole 5-hour window: that is exactly where
the 2026-10-18 batch hit `429 GoUsageLimitError`. So choose by spend ÷ limit, not token price:
deepseek-v4.1-flash ($80 limit, cheap tokens) is the most allowance-efficient Go model.

Before launching Go runs, check the window: `scripts/bench.sh --window` sums the allowance used in
the last 5 hours. Add an estimate for each run you're about to launch (the median for that model
and task size from `bench.sh`, or 5% while there's no data). Launch only while the total stays under
15%; anything that doesn't fit goes to a ChatGPT Plus model or waits. `scripts/cost.sh` reports cost
and allowance per run and model for any set of logs. When `run.sh` or `cost.sh` says a model is not
in `go-limits.tsv`, refresh the table from https://opencode.ai/v2/docs/console/go/ first.

### Trying new models

The roster is the user's decision; the benchmark (below) informs it. A model joins only after a
trial:

- A trial model runs as an **extra contestant** beside the roster model on the same brief, or as
  an **extra reviewer**. Its result is benchmarked and never merged unless it beats the roster
  model's result in your review.
- At most one trial run per task or per batch wave; skip trials when the 5-hour window is above 10%;
  prefer Plus models and Go models with $60+ limits.
- Trials only shadow tasks that touch no Never-change item and no protected path, because a winning
  trial result gets merged and your review must be enough on its own there.
- After 5+ benchmark records for a task type, show the user the numbers and let them decide whether
  it joins the roster for that task type. Edit the roster table only on their say-so.

Current trial group (from 2026-10-20): `openai/gpt-6-astra` (large and design-heavy, against
gpt-6.1-sol), `openai/gpt-6-luna` (mechanical and tests), and on Go `minimax-m3`, `qwen3.7-plus`,
`mimo-v2.6-flash` and `glm-5.3-flash` (general and fix-ups).

Not for delegation: `jev-1.13` (OpenCode free tier). It is a judgment and classification model, not
trained to generate text; a narrow classifier trial is parked in the skills repo's fog ledger.

Rules of thumb from past runs (ha-spark, October 2026):
- glm-5.2 on a large ticket can cost about $4, 7% of the month (#420, #422). For large tickets, use
  gpt-6.1-sol on the flat-rate Plus quota and keep glm-5.2 for its review.
- For reviews, deepseek-v4.1-flash cost about a sixth of glm-5.2 on the same brief ($0.09 against
  $0.56, #438), and a tenth of the allowance.
- A glm-5.2 review of gpt-6.1-sol's work has found real bugs more than once (#421: four). Don't
  skip it on large tickets.

## The route

This is the route for one task. For several tickets of one spec or map that land as one PR, read
[references/batch.md](references/batch.md): it adds a shared brief built by `scripts/brief.sh`, an
integration branch, dependency-ordered waves and a whole-batch review.

### 1. Read, then brief

Read the issue and the code it touches yourself. Then write the brief to a file, starting from
[assets/brief-template.md](assets/brief-template.md). The jail has no `gh`, no network beyond the model
providers and no view of this conversation, so the brief must carry:

- a pointer to the repo's conventions (AGENTS.md, CLAUDE.md, CONTRIBUTING.md);
- the issue text, verbatim;
- evidence the jail can't fetch: live payloads, API shapes, log excerpts, line numbers you found;
- the exact gate commands (lint, typecheck, tests);
- **every existing safety or fail-closed path the change must preserve, named explicitly** with
  `file:line`, and what "preserved" means for each.

The last point is the one that matters most. In the 2026-10-18 benchmark two of three models
silently relaxed a fail-closed guard to make their change work, and their own tests didn't catch
it. Models don't infer which guards are sacred; tell them, and tell them to stop and explain rather
than relax one.

### 2. Worktree

One linked worktree per task off the default branch:

```sh
git -C <repo> fetch origin
git -C <repo> worktree add -b <branch> <worktree-dir>/<name> origin/<default-branch>
```

For ha-spark the worktree dir is `~/ha-spark-wt/`. For other repos use `~/<repo>-wt/`. pi-jail
refuses the main checkout, so this step is not optional.

Before the first delegation in a repo, check whether `~/.config/pi-jail/protect/<repo-name>` exists.
If the repo has code delegates must not touch (hardware control, safety guards, auth, release
notes), propose a list to the user and add it once they agree: one path per line relative to the
repo root, trailing `/` for a directory, `#` comments allowed.

When a ticket must change a protected path, the default is to do that part yourself: delegate the
rest and tell the delegate the protected file is read-only. Lift a protect entry only when the user
agrees, for one run: copy the list to `<worktree-dir>/protect-<repo-name>.orig`,
remove only the entries the ticket needs, run, then restore the list from the copy
straight away, before reviewing. Treat changes to that path with extra care in review, and tell the
user in the report that the list was lifted and has been restored.

### 3. Run

```sh
~/skills/pi-delegate/scripts/run.sh <worktree> <provider/model> <brief-file> [log-name]
```

It wraps `pi-jail <worktree> -p --mode json --no-session -na --model <model> "<brief>" </dev/null`,
writes `<log>.pi.jsonl`, `.pi.err` and `.start` beside the worktree, and prints a summary (turns,
tool calls, tokens, cost per model, wall time, the delegate's final message). The log name defaults
to the worktree's name; give one whenever a worktree hosts more than one run (`416-review`,
`438-glm`), or the second run overwrites the first one's log. Keep the brief files beside the logs.

Runs take from a few minutes to over half an hour, so launch it with `run_in_background` and wait
for the exit notification rather than polling. If you call pi-jail directly, keep `</dev/null`
(`pi -p` hangs on stdin otherwise) and pass the brief as an argument (the jail's `/tmp` is private).
Re-summarise any log with `scripts/summarize.sh <log> [start-epoch]`.

**A run that dies on a provider error still exits 0 from pi.** `run.sh` checks for this and exits 3.
The summary's `ERROR:` line says why. On `429 GoUsageLimitError` the OpenCode Go window is spent:
don't retry. Move the run to `openai/gpt-6.1-sol` (Plus quota) if it suits the task, or tell the user
when the window resets and ask.

For a **bake off**, create one worktree per model (`<name>-glm`, `<name>-sol`, …), give each the
same brief, launch all runs in the same turn, then compare the diffs side by side: correctness,
whether each preserved the named safety properties, test quality, and cost.

For a **second-opinion review**, put a worktree on the branch under review and start from
[assets/review-brief-template.md](assets/review-brief-template.md). It works because it is narrow:
read-only, the test suite run at most once, the exact diff range, the safety properties as a
numbered list of rules to check line by line against the old path, and findings in a fixed shape
(file:line, triggering input, what happens, what should happen, "no findings" per rule, no praise).
Treat its findings like the delegate's summary, as claims you verify before fixing.

### 4. Review, outside the jail

The delegate's summary is a claim, not evidence. In the worktree:

1. Run the project's gates yourself.
2. Read the whole diff (`git -C <worktree> diff` plus `git status` for new files).
3. Probe each named safety property directly: read the guard as it now stands, check the tests that
   pin it still assert the same thing, and look for new fallbacks, broadened excepts, default-allow
   branches, deleted or loosened assertions, and skipped tests.
4. Check scope: nothing outside the expected files, nothing in the out-of-scope issues.

Fix small shortfalls yourself. Send larger ones back with a follow-up brief naming exactly what
failed (a fresh run with the original brief plus a "Previous attempt" section is cleanest, since
runs are `--no-session`).

### 5. Report and land

Tell the user: what changed, your concerns, which safety properties you probed and how, wall time,
and allowance used (OpenCode Go spend per model; OpenAI cost figures are notional because Plus is
flat-rate). Then commit and open the PR from the worktree, unless they said "hold the PR".

### 6. Clean up

Once the PR is merged or abandoned, remove its worktree (`git worktree remove <path>`, then
`git branch -d <branch>`). Keep the logs and briefs; they are the cost record. At the start of each
new delegation, run `git -C <repo> worktree list` and offer to remove any worktree whose branch is
already on the default branch and has a clean status.

## Safety: don't weaken

- pi has no sandbox and no approval prompts. Delegation always goes through `pi-jail`, never bare
  `pi` with tools in a real repo.
- pi-jail (bubblewrap) needs a linked worktree. It hides `~/.ssh`, `~/.config/gh`, `~/.claude`,
  `~/.codex` and the main checkout; makes `.env*` unreadable and the git dir read-only (no commits);
  mounts pi's own extensions and settings read-only; clears the environment; leaves the network on
  for the model providers.
- Protected paths in `~/.config/pi-jail/protect/<repo-name>` are enforced twice: read-only mounts
  in pi-jail and `~/.pi/agent/extensions/protected-paths.ts`.
- `~/.pi/agent/extensions/command-gate.ts` blocks git publish/commit, `gh`, curl/wget/ssh, package
  installs and sudo in delegated runs. If a task genuinely needs a new dependency, add it yourself
  before delegating.
- Delegates never get credentials, never commit or push, and never touch hardware or live services.
  Don't paste secrets or tokens into a brief.
- Never run jail-escape or write probes outside the jail. A 2026-10-18 control run clobbered pi's
  settings that way. If you need to test the jail, do it inside `pi-jail`.
