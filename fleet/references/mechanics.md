# Pi / opencode go mechanics and failure modes

Harness verified against Pi CLI v0.85.1, 2026-09-08 (research pass plus a
live smoke test through `scripts/fleet.sh`). Endpoint facts below carry
forward from the ccs era, where they were verified directly against
opencode's API; re-check them if `verify` starts disagreeing with this file.
Read this when an agent fails, when `status` reports something unexpected,
or before changing the script.

## opencode: `/zen` and `/zen/go` are different products

The single most expensive thing to not know about this fleet.

| Endpoint | What it is | State (2026-08-28, last checked) |
|---|---|---|
| `https://opencode.ai/zen/go/v1` | the $10/mo **subscription**, 33-model catalog | live, serving |
| `https://opencode.ai/zen/v1` | pay-as-you-go Zen, 64-model catalog | authenticates fine, `CreditsError` on every paid model — the workspace balance is $0 |
| `https://opencode.ai/go/v1` | nothing; returns the marketing site's HTML | — |

Pi's built-in `opencode-go` provider (`packages/ai/src/providers/opencode-go.ts`
in Pi's source) is pointed at the subscription path, `https://opencode.ai/zen/go`
— the same path the fleet's profiles route to. There is also a plain
`opencode` provider in Pi pointed at the unfunded PAYG `/zen` path; the fleet
does not use it. If a profile is ever pointed at it by mistake, expect the
same `CreditsError` the ccs era hit.

### The subscription: what it costs and where it runs

$10/month, flat, with a **$60 monthly usage cap shared across every model in
the go catalog**, measured at each model's own list price — see
`fleet/CONTEXT.md` and `docs/adr/0002-go-shared-cap-routing.md` for the
routing consequence. A cheap model stretches the month; an expensive one
burns it fast. None of the models bill a separate wallet — they only decide
how fast the shared cap empties.

**Models on go are China-hosted inference.** Serving them required enabling
opencode's China-hosting opt-in on the workspace. That is a data-residency
decision, not a performance one, and belongs in front of anyone routing
client work through this fleet.

### Anthropic-format support no longer matters here

Under the old ccs harness, opencode's Anthropic adapter covered only 6 of 33
go models server-side, which is why `glm-*` and `kimi-k2.7-code` used to
500 and were unroutable. **Pi talks to `opencode-go` over `/chat/completions`
(OpenAI format) natively**, so that restriction doesn't apply to Pi at all —
every model in the go catalog is reachable, including the ones ccs couldn't
reach. Keep this in mind if the routing table is ever widened past
`pi-default`/`pi-plus`/`pi-deepseek`: nothing in the go catalog is
format-blocked anymore, only unvalidated.

## Verified: Pi's headless command surface

```bash
pi -p "<prompt>" --model opencode-go/<model-id> \
   --session-dir <dir> --name <name>
```

| Flag | Effect | Verified |
|---|---|---|
| `-p "<text>"` | Print/headless mode: runs once, no TUI, exits when done | yes — used by every `launch`/`resume` |
| `--model <provider>/<id>` | Model for this run | yes — `opencode-go/minimax-m3` etc. all answered in `verify` |
| `--session-dir <dir>` | Where this run's session file is written | yes, points sessions at the fleet's own state dir rather than Pi's default `~/.pi/agent/sessions/<cwd>` |
| `--name <name>` | Names the session within `--session-dir`, for later addressing | used as the slug, so it lines up with the fleet's own naming |

**No TTY needed**: Pi forces print/non-interactive mode whenever stdin or
stdout isn't a TTY, even without `-p`. That's what makes `pi -p` safe inside
the script's detached `setsid` subshell.

**Exit codes**: `0` on success; `1` when the run ends in an error or is
aborted; `129`/`143` on SIGHUP/SIGTERM. `timeout` in the launch/resume
wrapper sends its own SIGTERM on the 30-minute cap and reports `124` itself
— unrelated to Pi's own exit codes, and `state_of` already treats `124` as
`timeout` regardless of which side produced it.

**No permission prompts, ever.** Pi has no built-in permission system — in
`-p` mode it reads, writes, and runs bash with the launching user's own
filesystem access, unconditionally. This is *why* every run gets its own
worktree, exactly as it was true of ccs: the worktree, not a flag, is the
safety boundary.

**Pi never commits on its own initiative.** There is no auto-commit logic in
Pi; if a brief tells it to commit, it runs `git commit` itself via its bash
tool (confirmed in the smoke test — the agent ran `git commit -q -m "..."`
inside the worktree because the brief asked it to). If a brief doesn't ask
for a commit, `land`'s own `stage_and_commit` step covers it.

## Auth and provider config

Pi's opencode-go key lives in `~/.pi/agent/auth.json` under the
`opencode-go` key, set via `pi login` (or by editing the file directly). The
fleet script reads it with `pi_key()` for its own preflight probe — never
`cat` this file into a transcript or a log; only the probe's *result* (the
provider's reply) should ever surface.

`~/.pi/agent/models.json` is where a genuinely custom OpenAI-compatible
endpoint would be added if the fleet ever needed one outside Pi's built-in
provider catalog. Not needed today: `opencode-go` and `deepseek` are both
native Pi providers.

## Every request needs an `x-opencode-session` header

OpenCode Go requires this header for routing/optimisation on their end; a
request missing it can be flagged as coming from a client they don't
recognise. **Pi attaches this automatically** for any model on the
`opencode`/`opencode-go` provider or any base URL on the `opencode.ai` host
— confirmed in Pi's source (`provider-attribution.ts`), which also sends
`x-opencode-client: pi`. The fleet script's own `probe_endpoint()` still sets
this header by hand with a fresh UUID per call, since a preflight probe is a
one-off outside any real Pi session.

## Cloudflare blocks the default Python user-agent

`opencode.ai` sits behind Cloudflare, which answers `Python-urllib/3.x` with
**HTTP 403 `error code: 1010`** — a bot-signature block. It looks exactly
like a dead profile. Any honest agent string is accepted; the preflight
sends `fleet-preflight/1`. Worth knowing before concluding a key is bad.

## AGENTS.md / CLAUDE.md handoff

Pi loads project context files walking from the worktree's cwd up to the
filesystem root, one per directory, preferring in order:
`AGENTS.override.md` → `AGENTS.md` → `CLAUDE.md`. So a repo with only a
`CLAUDE.md` needs no migration — Pi reads it as a fallback automatically.
Pi's own global `~/.pi/agent/AGENTS.md` (not the user's `~/.claude/CLAUDE.md`)
loads before the repo's file and is the place for fleet-wide process
conventions that should apply to every delegated agent regardless of repo —
see `docs/adr/0001-adopt-pi-as-the-fleet-harness.md` for why this replaced
carrying the harness's own weight into every headless run.

## Sessions and `resume` — verify before relying on it

Pi persists sessions as JSONL, one file per session, normally under
`~/.pi/agent/sessions/<cwd>/`. The fleet script instead passes
`--session-dir "$dir/sessions" --name "$slug"` on both `launch` and `resume`,
keeping each agent's session inside the fleet's own state directory (keyed
by slug, not by worktree path) so it isn't tied to a worktree that `clean`
will eventually delete.

**This has not been verified end to end.** The launch/status/diff/land/clean
loop was smoke-tested live and works; whether passing the same
`--session-dir`/`--name` pair on a second `pi -p` call actually continues the
first run's context (rather than starting a fresh session that happens to
share a directory) has not been confirmed with a real multi-turn test. Run
one before trusting `resume` on anything that matters — launch an agent,
resume it with something only "remembering" the first turn would answer
correctly, and check the log.

## State layout

`$PI_FLEET_HOME` (default `~/.pi/fleet`), deliberately outside the repo so
worktrees never show up in `git status`:

```
~/.pi/fleet/<repo-name>/<slug>/
├── meta.json     slug, profile, model, repo, worktree, branch, base, base_sha, started
├── brief.md      the prompt as sent
├── run.log       raw pi stdout+stderr
├── sessions/     this agent's Pi session file(s), addressed by --name <slug>
├── pid           written by the runner itself on start
└── exit_code     written by the runner itself on finish
```

State is read from the filesystem, not a shell job table: `launch` returns
immediately and its job table dies with it. `pid` plus `exit_code` is what
makes `status` still meaningful minutes later, from a different shell.

Two consequences worth knowing. `died` means the runner vanished without
writing `exit_code` — an OOM kill or a reboot, usually; `run.log` is the
place to look. And exit `124` is `timeout` firing at `PI_FLEET_TIMEOUT`
(default 1800s), not a model failure.

There is no `tool` field in `meta.json` the way the ccs/agy era needed one —
Pi is the only tool this script drives, so nothing branches on it anymore.

## Landing and build artifacts

`land` stages with `git add -A` so that new files the agent created (usually
the whole point) get committed. That alone would also sweep up anything
ephemeral the agent or your verification run left behind, and a repo with no
`.gitignore` has no defence — this really happened during the ccs-era
evaluation, putting `__pycache__` `.pyc` files into two merge commits.

So `land` layers an artifact pattern list over the repo's own `.gitignore`
via `core.excludesFile`, then reports the difference between what plain
`add -A` would have taken and what it actually took. Filtering without
disclosure would be worse than the original bug: it could silently discard
real work. Override with `PI_FLEET_EXCLUDES_FILE=<path>` for
project-specific patterns.

## Error codes

| Symptom | Cause | Fix |
|---|---|---|
| `no opencode-go key in ~/.pi/agent/auth.json` | Pi was never authenticated on this machine | `pi login` |
| HTTP 401 `CreditsError` | The go subscription's $60 shared cap is spent | Wait for the monthly reset, or route to `pi-deepseek` only on explicit request |
| HTTP 401 `RegionError` | opencode's China-hosting opt-in is off for the workspace | Re-enable it in the opencode workspace settings |
| HTTP 401 `ModelError: not supported` | Model id is wrong for the go endpoint | Check the id against `pi --list-models` or the fleet's own profile table |
| HTTP 403 `error code: 1010` | Cloudflare blocked the client's user-agent, not an auth failure | Send any honest `User-Agent` (the preflight already does) |
| HTTP 429 | Rate limited, or the shared cap tripped mid-run | Read `log <slug>`; stagger launches |
| exit 124 | Hit `PI_FLEET_TIMEOUT` | Split the task, or raise the limit |
| `done` but `0 file(s)` | Agent decided nothing needed doing, misread the brief, or narrated an edit without making the tool call | Read `run.log`; usually the brief was ambiguous or didn't say to *act*, not just describe |

Config lives in `~/.pi/agent/` (`auth.json`, `settings.json`,
`models-store.json`, `trust.json`, `sessions/`) — not XDG-standard
(`~/.config/pi`), which is a known open issue upstream; don't go looking for
config there.

## Note on credentials

`~/.pi/agent/auth.json` holds the live opencode-go API key in plaintext.
Never `cat` it into a transcript, and never include it in a brief — a
delegated agent has no need for it; Pi injects the env itself.

## Version pinning

Pi is young (public launch ~Feb 2026) and ships breaking changes between
minor versions — the 0.84→0.85 line renamed a thinking-level type, for
example. This file and the fleet script were verified against **v0.85.1**.
Re-verify (`$F verify`, plus a real smoke-test `launch`) after any `pi
update --self` before trusting the fleet again.
