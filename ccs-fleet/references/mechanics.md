# CCS mechanics and failure modes

Verified against CCS CLI v8.9.0 on 2026-08-18. Read this when an agent fails,
when `status` reports something unexpected, or before changing the script.

## Verified command surface

```bash
ccs <profile> [claude-args...] -p "<prompt>"
```

`ccs` sets the profile's env (from `~/.ccs/<profile>.settings.json`) and execs a
headless `claude`. Anything else on the line is passed through to `claude`, so
the flags that matter are Claude Code's own:

| Flag | Effect | Verified |
|---|---|---|
| `-p "<text>"` | Headless run with this prompt | yes |
| `--model <id>` | Really does switch model, despite the summary table | yes — `--model deepseek-v4-flash` shows `{"model":"deepseek-v4-flash"}` on stderr |
| `--session-id <uuid>` | Run under a caller-chosen session id | yes |
| `--resume <uuid>` | Continue that session, from the same cwd | yes |

Agents write files unattended in `-p` mode — no permission prompt, no
confirmation. This is the single most important property of the tool and the
reason every run gets its own worktree.

## `<profile>:continue` no longer exists

`ccs deepseek:continue -p "..."` fails with **error E104** ("profile not
found") on v8.9.0. The syntax appears in CCS's own bundled `ccs-delegation`
skill and in `~/.claude/commands/ccs/continue.md`, both of which are stale.

Continuation is `--resume <session-id>`, which is why `launch` generates a UUID
up front and stores it in `meta.json`.

## Why the script assigns session ids

CCS records sessions in `~/.ccs/delegation-sessions.json` keyed as
`<profile>:latest` — one slot per profile. Launch three `deepseek` agents at
once and whichever finishes last owns the slot; the other two become
unresumable. The summary table's `Session` column is truncated to 8 characters
and cannot be fed back to `--resume`.

Passing `--session-id` sidesteps both problems: the id is known before the agent
starts and belongs to that agent alone.

## State layout

`$CCS_FLEET_HOME` (default `~/.ccs/fleet`), deliberately outside the repo so
worktrees never show up in `git status`:

```
~/.ccs/fleet/<repo-name>/<slug>/
├── meta.json     slug, profile, model, session_id, repo, worktree, branch, base_sha, started
├── brief.md      the prompt as sent
├── run.log       raw CCS stdout+stderr
├── pid           written by the runner itself on start
└── exit_code     written by the runner itself on finish
```

State is read from the filesystem, not a shell job table: `launch` returns
immediately and its job table dies with it. `pid` plus `exit_code` is what makes
`status` still meaningful minutes later, from a different shell.

Two consequences worth knowing. `died` means the runner vanished without writing
`exit_code` — an OOM kill or a reboot, usually; `run.log` is the place to look.
And exit `124` is `timeout` firing at `CCS_FLEET_TIMEOUT` (default 1800s), not
a model failure.

## Landing and build artifacts

`land` stages with `git add -A` so that new files the agent created (usually the
whole point) get committed. That alone would also sweep up anything ephemeral
the agent or your verification run left behind, and a repo with no `.gitignore`
has no defence — this really happened during evaluation, putting `__pycache__`
`.pyc` files into two merge commits.

So `land` layers an artifact pattern list over the repo's own `.gitignore` via
`core.excludesFile`, then reports the difference between what plain `add -A`
would have taken and what it actually took. Filtering without disclosure would
be worse than the original bug: it could silently discard real work. Override
with `CCS_FLEET_EXCLUDES_FILE=<path>` for project-specific patterns.

## Error codes

| Symptom | Cause | Fix |
|---|---|---|
| `Error: E104` | Profile name not in `~/.ccs/config.yaml`, or `:continue` syntax | Check `profiles:` in the config; use `--resume` |
| HTTP 401 | Token in `~/.ccs/<profile>.settings.json` rejected | Re-issue the key at the provider |
| HTTP 429 | Rate limited — common on nvidia's free tier under fan-out | Stagger launches, or move some tasks to deepseek |
| exit 124 | Hit `CCS_FLEET_TIMEOUT` | Split the task, or raise the limit |
| `done` but `0 file(s)` | Agent decided nothing needed doing, or misread the brief | Read `run.log`; usually the brief was ambiguous |

Config lives in `~/.ccs/config.yaml`. There is no `config.json` on this machine —
the stale bundled skill's instruction to read one is wrong, and following it
yields "file not found".

## Note on credentials

`~/.ccs/*.settings.json` hold live API tokens in plaintext. Never `cat` them
into a transcript, and never include them in a brief — a delegated agent has no
need for them; `ccs` injects the env itself.
