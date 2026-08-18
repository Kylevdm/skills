# CCS/agy mechanics and failure modes

Verified against CCS CLI v8.9.0 and the `agy` (Antigravity) CLI on
2026-08-18. Read this when an agent fails, when `status` reports something
unexpected, or before changing the script.

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
├── meta.json     slug, profile, tool, model, session_id, repo, worktree, branch, base_sha, started
├── brief.md      the prompt as sent
├── run.log       raw CCS/agy stdout+stderr
├── pid           written by the runner itself on start
└── exit_code     written by the runner itself on finish
```

`tool` (`ccs` or `agy`) is what every tool-shaped decision in the script
branches on — argv construction, resume semantics, session-id capture timing.
It's derived once at launch from the profile name (`tool_for_profile()`) and
stored so later commands (`resume`, `status`) don't have to re-derive it.
Runs launched before this field existed read back as an empty string;
`resume` treats that as `ccs` for backward compatibility, `status` just shows
an empty TOOL column for them.

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
| HTTP 429 | Rate limited under fan-out | Stagger launches |
| exit 124 | Hit `CCS_FLEET_TIMEOUT` | Split the task, or raise the limit |
| `done` but `0 file(s)` | Agent decided nothing needed doing, or misread the brief | Read `run.log`; usually the brief was ambiguous |
| agy `status: "ERROR"` | See the `error` field — bad `--model`, quota/billing limit, or a genuine tool failure | Fix the cause named in `error`; route to `deepseek` if it's a limit |
| agy `done` but `0 file(s)` and worktree untouched | Ran without `--add-dir` on the worktree (shouldn't happen via the script, but check if hand-editing) | Confirm `--add-dir <worktree>` is present in the argv; check `response` text for a mention of the scratch folder |

Config lives in `~/.ccs/config.yaml`. There is no `config.json` on this machine —
the stale bundled skill's instruction to read one is wrong, and following it
yields "file not found".

## Note on credentials

`~/.ccs/*.settings.json` hold live API tokens in plaintext. Never `cat` them
into a transcript, and never include them in a brief — a delegated agent has no
need for them; `ccs` injects the env itself.

## agy (Antigravity) mechanics

`agy` is a genuinely different tool from `ccs`, not another profile on the same
shape — three of its behaviors are surprising enough that they shaped how the
script talks to it.

### Verified command surface

```bash
agy --model <id> --dangerously-skip-permissions --add-dir <dir> \
    --output-format json -p "<prompt>"
```

| Flag | Effect | Verified |
|---|---|---|
| `--model <id>` | Model for this run, by slug (`agy models` lists them) | yes |
| `--dangerously-skip-permissions` | Required for unattended `-p` runs — without it, tool calls block on a permission prompt that never resolves headless | yes |
| `--add-dir <dir>` | Grants trust for a directory for this run | yes — see below, this is not optional |
| `--output-format json` | Prints one JSON object to stdout instead of prose | yes |
| `--conversation <id>` | Resume that conversation, same workspace context | yes |

Like CCS in `-p` mode, agy writes files unattended once permissions are
skipped — same reason every run gets its own worktree.

### `--add-dir` is not optional

agy only writes into directories listed in its own
`~/.gemini/antigravity-cli/settings.json` under `trustedWorkspaces`. Run it
from an untrusted directory (which every fresh worktree is, by construction)
and it does **not** error — it silently redirects file writes to its own
scratch folder (`~/.gemini/antigravity-cli/scratch`) instead, and reports
success. Verified directly: a run without `--add-dir` from inside a plain
worktree wrote `README.md` into the scratch folder and said so in its own
`response` text, while the worktree stayed untouched. Passing `--add-dir
<worktree>` on every launch and resume is what makes the run land where it's
supposed to; skipping it produces a `done` agent with a `1 file(s)` diff of
nothing, in a folder the script never checks.

### Session ids run backwards from CCS

CCS wants a session id supplied up front (`--session-id`); agy generates its
own and hands it back as `conversation_id` in the JSON response once the run
finishes. That's why `launch` leaves `session_id` empty in `meta.json` for
agy runs until the detached runner's finish step (`cmd_finish` /
`agy_conversation_id`) parses it out of `run.log` after the process exits.
Resuming before a run has ever finished (`session_id` still empty) fails
loudly rather than resuming nothing — `resume` checks for this explicitly.
Verified that `--conversation <id>` on a second call keeps the *same*
`conversation_id` in its response, so no re-parsing is needed after a resume.

### Output and errors are structured, and more honest than CCS's

With `--output-format json`, every run — success or failure — prints exactly
one JSON object:

```json
{"conversation_id": "...", "status": "SUCCESS", "response": "...",
 "duration_seconds": 6.9, "usage": {"input_tokens": ..., "total_tokens": ...}}
```

or, on failure:

```json
{"conversation_id": "", "status": "ERROR", "response": "",
 "error": "invalid model selection (...): model <x> is not recognized ..."}
```

Verified: an invalid `--model` value produced this shape with process exit
code `1`. Unlike CCS, there's no fabricated cost figure and no
model-that-silently-didn't-apply — `status`, `error`, and `usage` can all be
trusted directly. `agy_conversation_id()` in the script deliberately scans
`run.log` from the end and takes the last JSON-shaped line, in case anything
else ever ends up ahead of it in the log.

### `gpt-oss-120b-medium` (`agy-oss`) can report success without editing

Verified 2026-08-18: on a one-line, loosely worded brief, `agy-oss` returned
`status: "SUCCESS"` with prose describing the edit it claimed to make, but
the worktree was untouched (`0 file(s)` in `status`, empty `diff`) — not the
`--add-dir` scratch-folder trap above, just the model narrating a tool call
it never issued. Re-running the identical task with a brief that explicitly
says to use the file-editing tool and confirm the save succeeded end to end.
Treat a `done` `agy-oss` run with `0 file(s)` as reason to read `response` in
`log <slug>` before relaunching — the model may just need a more explicit
instruction to act rather than describe, not a different profile.
