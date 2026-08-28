# CCS/agy mechanics and failure modes

Verified against CCS CLI v8.9.0 and `agy` v1.1.22, on 2026-08-18 and
2026-08-28. Read this when an agent fails, when `status` reports something
unexpected, or before changing the script.

## opencode: `/zen` and `/zen/go` are different products

The single most expensive thing to not know about this fleet.

| Endpoint | What it is | State (2026-08-28) |
|---|---|---|
| `https://opencode.ai/zen/go/v1` | the $10/mo **subscription**, 33-model catalog | live, serving |
| `https://opencode.ai/zen/v1` | pay-as-you-go Zen, 64-model catalog | authenticates fine, `CreditsError` on every paid model — the workspace balance is $0 |
| `https://opencode.ai/go/v1` | nothing; returns the marketing site's HTML | — |

Both accept the same key, via either `x-api-key` or `Authorization: Bearer`.

All four `oc-*` profiles were originally pointed at the PAYG path, so every
request came back HTTP 401 `CreditsError: Insufficient balance`. Claude Code's
SDK maps 401 to `authentication_failed` and retries it ten times behind
exponential backoff, so what the user saw was a **118-second hang ending in a
generic auth error** — the actual message, which names its own fix, never
surfaced. One wrong path segment, an entire debugging session, and a
near-miss architectural rewrite. `verify` and the launch preflight exist
because of this: both ask for 24 real tokens and print the upstream's own
`error.message` in under a second.

A `/v1/models` listing would **not** have caught it. The unfunded endpoint
answers that with a clean 200. Only generation fails, so only generation is a
real probe.

### The subscription: what it costs and where it runs

$10/month, flat, with a **$60 monthly usage cap** measured at the models' own
list prices. Per Mtok, from `~/.ccs/models-dev-registry-cache.json`:
`deepseek-v4-flash` 0.14/0.28 · `deepseek-v4-pro` 0.44–1.74/0.87–3.48 ·
`kimi-k3` 3/15. None of these bill the wallet directly — they decide **how
fast the cap burns**, and `kimi-k3` burns it 4–8× faster than
`deepseek-v4-pro`. The `deepseek` profile is a separate PAYG account and is
scoped as the overflow for when the cap does run out.

**DeepSeek on opencode is China-hosted inference.** Serving it required
enabling opencode's China-hosting opt-in on the workspace (before that, every
`deepseek-v4-*` call returned `RegionError: requires explicit opt in`); the
same opt-in is what unlocked `kimi-k3` and both Qwen Max models. So
`oc-fast`, `oc-smart`, and `oc-free` all route code to China-hosted inference.
That is a data-residency decision, not a performance one, and it belongs in
front of anyone routing client work.

Zen's BYOK feature accepts only OpenAI and Anthropic keys, so the user's
DeepSeek key cannot be attached to the opencode workspace. That is why
`deepseek` stays a separate `ccs` profile rather than folding into Zen.

### Anthropic format support is per-model, and mostly absent

opencode's Anthropic adapter covers **6 of the 33** go models. This is
server-side; no config fixes it. Verified 2026-08-28 with a 24-token
`/v1/messages` POST:

| Model | `/v1/messages` | `/chat/completions` |
|---|---|---|
| `deepseek-v4-flash`, `deepseek-v4-pro` | ✅ | ✅ |
| `qwen3.8-max`, `qwen3.7-max` | ✅ | ✅ |
| `kimi-k3`, `minimax-m3` | ✅ | ✅ |
| `glm-5.3`, `glm-5.2`, `kimi-k2.7-code` | ❌ 500 | ✅ |
| `gpt-5.6-luna` | ❌ 500 | ❌ 500 |
| `grok-4.6` | ❌ `not supported for format anthropic` | ❌ `not supported for format oa-compat` |
| `deepseek-v4-pro[1m]` | ❌ `ModelError: not supported` | ❌ |

Three consequences the profile set is built around. **`grok-4.6` is
unavailable in every API format**, so it cannot back any profile. **`[1m]` is
rejected on go** — the suffix works only against DeepSeek's own API, which is
why `deepseek` keeps it and no `oc-*` profile has it. And go serves **no
Claude and no Gemini** (`gpt-5.6-luna` is its only frontier-adjacent model,
and it 500s), which is why `agy` is not redundant.

go's context window is not published — the catalog exposes no limit metadata —
but it is roomy. Measured 2026-08-28 on `deepseek-v4-flash`: a prompt with a
passphrase at the very front followed by ~250k tokens of filler came back with
the passphrase recalled correctly, no error and no sign of head truncation, at
100k and 250k alike.

Two caveats keep that from being a long-context *quality* claim. A
low-entropy haystack is the easiest possible retrieval test, so this shows
the plumbing carries ~250k tokens, not that reasoning holds up across them.
And the `usage.input_tokens` figures that come back are not trustworthy — the
same prompt reported 88, 5,808, and 151,808 across runs, which is prompt
caching being counted inconsistently rather than the input changing size.
Don't use them to estimate cap burn. For work that genuinely needs a huge
window, `deepseek` and its `[1m]` suffix remain the honest answer.

### Measured: Qwen 3.8 Max does not beat DeepSeek V4 Pro here

An `oc-max` tier on `qwen3.8-max` was built and then deleted on the strength
of an A/B, recorded so nobody rebuilds it on the same reasoning.

Identical brief, identical fixture, two worktrees: extend a flat
`parse_config()` to support nested `[section]` and dotted `[a.b]` headers with
full backward compatibility, exact `ValueError` line numbers, and repeated
sections merging. Graded by a 16-case suite neither agent could see (the
untouched baseline scores 7/16).

| Profile | Model | Score | Duration | Diff |
|---|---|---|---|---|
| `oc-smart` | `deepseek-v4-pro` | **16/16** | 188s, 8 turns | +22/-4 |
| `oc-max` | `qwen3.8-max` | **16/16** | 365s, 1.9× slower | +32/-4 |

Both stayed in scope. Qwen matched on correctness and lost on everything
else, while burning the cap faster — so there is nothing between `oc-smart`
and `agy-opus`, and hard reasoning is not by itself a reason to escalate.
This matches the grill-time ordering, which put Qwen Max at or below DeepSeek
V4 Pro; with `grok-4.6` unavailable in every format, nothing in go's catalog
clearly beats `deepseek-v4-pro`.

`qwen3.8-max` still works and is still worth `--model qwen3.8-max` on
`oc-smart` when a second opinion from a different model family is the point.
One task is one data point; re-run something like this before reinstating a
tier on it.

### Free models exist only on PAYG, only in OpenAI format

The free ids (`hy3-free`, `mimo-v2.5-free`, `laguna-s-2.1-free`,
`nemotron-3.5-lightning-free`, …) are in the PAYG catalog and not in go's 33.
They answer at a $0 balance, but **every one of them 500s on
`/v1/messages`** — they are reachable only through `/chat/completions`.

That this is server-side rather than a local misconfiguration was confirmed
by control: a *paid* model on the identical endpoint, key, and headers
returns a clean, well-formed `CreditsError`. Auth and transport are fine; the
Anthropic adapter simply does not cover the free models.

**Free ids rot fast.** Verified in one sitting on 2026-08-28: `hy3-free` ✅
200, `laguna-s-2.1-free` ✅ 200, `mimo-v2.5-free` ❌ 429 `FreeUsageLimitError`,
`deepseek-v4-flash-free` ❌ 400 "Model is unavailable",
`ling-3.0-flash-fin-free` ❌ 503, `nemotron-3.5-lightning-free` ❌ 400. Treat
whichever id `oc-free` names as disposable: `verify` tells you when it dies,
`--model <other-free-id>` swaps it for one run, and the profile table in the
script is where a lasting swap goes.

### `ccs` has a built-in Anthropic→OpenAI proxy, and starts it itself

`ccs proxy start <profile>` runs a local daemon that accepts Anthropic
`/v1/messages` inbound and calls `chat/completions` upstream — verified by a
404 on inbound `/chat/completions`, `owned_by: generic-chat-completion-api`
in its model list, and `ccs proxy activate` emitting
`export ANTHROPIC_BASE_URL='http://127.0.0.1:<port>'`. Against `glm-5.3`, a
model that 500s on the native Anthropic path, the translation is production
quality: tool calls arrive as a valid `tool_use` block with parsed `input`
JSON and `stop_reason: tool_use`, reasoning maps into `thinking` blocks with
synthesized signatures, and streaming produces a well-formed Anthropic SSE
sequence.

**The fleet script does not manage this daemon, and must not start one.**
`ccs` does it automatically: `settings-flow.js` calls
`resolveOpenAICompatProfileConfig()` on every profile it launches, and if the
profile resolves to an OpenAI-compatible provider it calls
`startOpenAICompatProxy()`, exits 1 with a clear stderr message if that
fails, and otherwise prints `Using local OpenAI-compatible proxy for "<name>"
on port <n>`. Verified directly: `ccs proxy stop oc-free`, then a plain
`ccs oc-free -p ...`, and the daemon comes back under a new PID. So `oc-free`
is invoked exactly like every other ccs profile.

The switch is **`CCS_DROID_PROVIDER` in the settings file**, and it is
load-bearing rather than cosmetic:

- `generic-chat-completion-api` (or `openai`) → ccs owns a proxy for this
  profile and talks OpenAI upstream. This is what makes `oc-free` work at all.
- anything else, `anthropic` included → ccs goes straight at the upstream's
  `/v1/messages`.

`ccs api create` writes `generic-chat-completion-api` for any base URL it
doesn't recognise, opencode's included, so a freshly provisioned `oc-smart`
would sit behind a proxy it does not need. `provision` corrects the field
afterwards and `verify` reports it as drift.

The upstream path the proxy calls is derived in `proxy/upstream-url.js`: a
base that ends in `/v1` or `/api` gets `/chat/completions` appended, anything
else gets `/v1/chat/completions`. So `https://opencode.ai/zen` resolves to
`https://opencode.ai/zen/v1/chat/completions`, which is correct.

**Do not deploy the Cloudflare Worker** from
`github.com/cucoleadan/opencode-cowork-proxy`. It solves exactly the problem
`ccs proxy` already solves locally, and pays for it by routing every request
and the API key through third-party infrastructure.

### Cloudflare blocks the default Python user-agent

`opencode.ai` sits behind Cloudflare, which answers `Python-urllib/3.x` with
**HTTP 403 `error code: 1010`** — a bot-signature block. It looks exactly
like a dead profile. Any honest agent string is accepted; the preflight sends
`fleet-preflight/1`. Worth knowing before concluding a key is bad.

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
| HTTP 401 `CreditsError` | The go subscription's $60 monthly cap is spent, or the profile is pointed at the unfunded PAYG `/zen` | `fleet.sh verify` names which; route to `deepseek` for the former, fix the base URL for the latter |
| HTTP 401 `RegionError` | opencode's China-hosting opt-in is off for the workspace | Re-enable it in the opencode workspace settings |
| HTTP 401 `ModelError: not supported` | Model id is wrong for that endpoint/format — `[1m]` on go, or `grok-4.6` anywhere | Pick an id from the format table above |
| HTTP 401 (generic, after ~118s) | The retry loop ate the real message | `fleet.sh verify <profile>` — it prints what the provider actually said |
| HTTP 403 `error code: 1010` | Cloudflare blocked the client's user-agent, not an auth failure | Send any honest `User-Agent` |
| HTTP 429 `FreeUsageLimitError` | `oc-free`'s model hit its free-tier limit | `--model <another-free-id>`, or wait |
| HTTP 500 on `/v1/messages` | That model has no Anthropic adapter server-side | Give the profile `CCS_DROID_PROVIDER: generic-chat-completion-api` so ccs proxies it |
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

### A model can report success without ever editing

Verified 2026-08-18 on `gpt-oss-120b-medium` (a profile since dropped, but
the failure mode is not model-specific): given a one-line, loosely worded
brief, it returned `status: "SUCCESS"` with prose describing the edit it
claimed to make, while the worktree stayed untouched — `0 file(s)` in
`status`, empty `diff`. Not the `--add-dir` scratch-folder trap above; just a
model narrating a tool call it never issued. Re-running the identical task
with a brief that explicitly said to use the file-editing tool and confirm
the save succeeded end to end.

So a `done` run with `0 file(s)` is a reason to read the log before
relaunching, on any profile. The fix is usually a brief that says to act
rather than describe, not a different model. It is also why the smoke test
in the update skill grades on a non-empty diff rather than an exit code.
