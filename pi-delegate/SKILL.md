---
name: pi-delegate
description: Delegate coding work to cheaper models through pi inside pi-jail, while Claude stays the orchestrator that plans, briefs, reviews every diff, runs the gates and commits. Use when the user says "delegate #N", "send #N to pi", "delegate to gpt/glm/kimi", "bake off #N", "pi-jail", "hold the PR", or asks to hand an issue, fix, test-writing job or second-opinion review to another model to save Claude usage. Also use when deciding unprompted whether a task should be delegated or done directly.
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
| "do #N yourself" | No delegation |
| "…, hold the PR" | Stop after review; the user approves before commit/PR |
| nothing | Decide per task and say which route you picked and why |

## Roster

| Work | Model |
|---|---|
| General fixes (default) | `opencode-go/glm-5.2` |
| Larger multi-file or design-heavy work; second-opinion reviews | `openai/gpt-6.1-sol` (ChatGPT Plus quota) |
| Mechanical edits, writing tests, lint/type fix-ups | `opencode-go/kimi-k2.7-code` |
| Cheap, fast, large-context sweeps (off-peak) | `opencode-go/deepseek-v4.1-flash` |
| Throwaway prototypes | `opencode-go/longcat-2.5-preview-free` |

- When reviewing gpt-6.1-sol's own output, use glm-5.2, so it isn't grading itself.
- **Never** `openai/gpt-6-sol`. **Avoid unless asked:** Kimi K3, Grok 4.7, Qwen3.8 Max, GLM-5.3 and any
  direct `deepseek/*` model (paid credits; OpenCode Go serves the same models). `scripts/run.sh`
  refuses the never/paid ones.
- The ChatGPT account only accepts newer models: gpt-6.1-sol works; gpt-5.5 / 5.3-codex / 5.4-mini
  return 400.
- OpenCode Go is one allowance: each model's spend ÷ that model's monthly limit, summed (5 h window
  = 20%, week = 50%). Choose by spend ÷ limit, not token price. Limits:
  https://opencode.ai/v2/docs/console/go/
- pi's default model is `opencode-go/kimi-k2.7-code`, so a forgotten `--model` costs little, but pass
  it every time anyway.

## The route

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

### 3. Run

```sh
~/skills/pi-delegate/scripts/run.sh <worktree> <provider/model> <brief-file>
```

It wraps `pi-jail <worktree> -p --mode json --no-session -na --model <model> "<brief>" </dev/null`,
writes `<worktree>.pi.jsonl`, `.pi.err` and `.start` beside the worktree, and prints a summary
(turns, tool calls, tokens, cost per model, wall time, the delegate's final message). Runs take
from a few minutes to over half an hour, so launch it with `run_in_background` and wait for the exit
notification rather than polling. If you call pi-jail directly, keep `</dev/null` (`pi -p` hangs on
stdin otherwise) and pass the brief as an argument (the jail's `/tmp` is private). Re-summarise any
log with `scripts/summarize.sh <log> [start-epoch]`.

For a **bake off**, create one worktree per model (`<name>-glm`, `<name>-sol`, …), give each the
same brief, launch all runs in the same turn, then compare the diffs side by side: correctness,
whether each preserved the named safety properties, test quality, and cost.

For a **second-opinion review**, put a worktree on the branch under review and brief the reviewer
with the issue, the diff range (`git diff <base>...HEAD`), the safety properties, and an instruction
to report findings without editing files.

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
flat-rate). Then commit and open the PR from the worktree, unless they said "hold the PR". Remove the
worktree once the PR is merged or abandoned (`git worktree remove`).

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
