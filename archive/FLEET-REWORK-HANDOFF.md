# Handoff: rework `ccs-fleet` → `fleet`

> Produced by a grilling session on 2026-08-28. **Supersedes the previous
> handoff of the same name**, which was built on two wrong premises — see
> [Corrections](#corrections-to-the-previous-handoff).
>
> Execute by invoking the **`ccs-fleet-update`** maintenance skill, which keeps
> the script, SKILL.md, mechanics.md, evals, and **both install locations** in
> sync. Do **not** hand-edit the skill files.
>
> Install locations that must stay in sync:
> - `/home/splungent/Development/skills/ccs-fleet/` (repo; `ccs-fleet` is a
>   symlink to `/home/splungent/skills/ccs-fleet`)
> - the plugin/cache copy the runtime loads
>
> Repo: `/home/splungent/Development/skills`, branch `add-ccs-fleet-update-skill`.
> **Nothing has been implemented yet.** No skill files were touched.

## The root cause (why the fleet was broken)

The four `oc-*` profiles in `~/.ccs/` pointed at **`https://opencode.ai/zen`** —
the PAYG Zen gateway, whose workspace balance is **$0**. The subscription lives
at a different path, **`https://opencode.ai/zen/go`**, which the previous
handoff did not know existed.

Every request therefore returned:

```json
{"type":"error","error":{"type":"CreditsError","message":"Insufficient balance."}}
```

HTTP 401. Claude Code's SDK maps 401 → `authentication_failed` and retried ten
times with exponential backoff, producing a **118-second hang** ending in a
generic auth error. The real message was destroyed by the retry loop. That
masking is what sent the previous session down an architectural rewrite when
the fix was one path segment.

## Verified ground truth (2026-08-28)

All of this was confirmed empirically with the user's key. Re-verify with
`curl` against `/v1/models` and a 24-token `/v1/messages` POST before trusting
any of it — opencode's catalog and per-model format support both churn.

### Endpoints

| Endpoint | Purpose | State |
|---|---|---|
| `https://opencode.ai/zen/v1` | PAYG Zen, 63-model catalog | ✅ auth OK, ❌ `CreditsError` on all **paid** models ($0 balance) |
| `https://opencode.ai/zen/go/v1` | **The $10/mo subscription**, 32-model catalog | ✅ live and serving |
| `https://opencode.ai/go/v1` | — | ❌ does not exist (returns the marketing site HTML) |
| `https://api.deepseek.com/anthropic` | existing `deepseek` profile | ✅ HTTP 200 clean |

Both endpoints accept `x-api-key` and `Authorization: Bearer` with the same key.

### Per-model format support on `zen/go`

opencode's Anthropic adapter covers only **6 of 32** go models. This is
server-side and per-model — not a config error, and not fixable by us.

| Model | Anthropic `/v1/messages` | OpenAI `/chat/completions` |
|---|---|---|
| `deepseek-v4-pro` | ✅ | ✅ |
| `deepseek-v4-flash` | ✅ | ✅ |
| `qwen3.8-max` | ✅ | ✅ |
| `qwen3.7-max` | ✅ | ✅ |
| `kimi-k3` | ✅ | ✅ |
| `minimax-m3` | ✅ | ✅ |
| `glm-5.3`, `glm-5.2` | ❌ 500 | ✅ |
| `kimi-k2.7-code` | ❌ 500 | ✅ |
| `gpt-5.6-luna` | ❌ 500 | ❌ 500 |
| `grok-4.6` | ❌ `not supported for format anthropic` | ❌ `not supported for format oa-compat` |
| `deepseek-v4-pro[1m]` | ❌ `ModelError: not supported` | ❌ |

**`grok-4.6` is unavailable in every API format.** The previous handoff's
`oc-max` tier is dead as specified.

**The China-hosting opt-in has been enabled** by the user during this session.
Before that, `deepseek-v4-*` returned `RegionError`. This unlocked not just
DeepSeek but `kimi-k3` and both Qwen Max models. **The `oc-*` DeepSeek profiles
route code to China-hosted inference** — this must be stated in SKILL.md so
client work is not routed there by reflex.

### Free models

Free ids (`mimo-v2.5-free`, `hy3-free`, `big-pickle`, `nemotron-3-ultra-free`,
…) exist **only in the PAYG Zen catalog**, not in go's 32. They answer at $0
balance, but **only on `/chat/completions`** — every one returns 500 on
`/v1/messages`.

Control experiment proving this is server-side and not a local misconfiguration:
a *paid* model on the identical endpoint, key, and headers returns a clean
well-formed `CreditsError`. Auth and transport are fine; the Anthropic adapter
simply does not handle the free models.

Observed: `mimo-v2.5-free` ✅ 200, `hy3-free` ✅ 200, `big-pickle` ❌ 429
`FreeUsageLimitError`, `nemotron-3-ultra-free` ❌ 60s timeout. Free ids rot —
treat any specific id as disposable.

### CCS has a built-in Anthropic→OpenAI proxy

**This is the most important finding and it removes an external dependency.**

`ccs proxy start <profile>` runs a local daemon that accepts Anthropic
`/v1/messages` **inbound** and calls `chat/completions` **upstream**. Confirmed
by: 404 on inbound `/chat/completions`; `owned_by: generic-chat-completion-api`
in its model list; and `ccs proxy activate` emitting
`export ANTHROPIC_BASE_URL='http://127.0.0.1:<port>'`.

Verified against `glm-5.3` — a model that 500s on the native Anthropic path:

- **Tool calls translate correctly**: `stop_reason: tool_use`, a valid
  `tool_use` block with parsed `input` JSON.
- **Reasoning** is mapped into `thinking` blocks with synthesized signatures.
- **Streaming** produces a well-formed Anthropic SSE sequence: `message_start`,
  `content_block_start`, 99× `content_block_delta`, `content_block_stop`,
  `message_delta`, `message_stop`.

A live daemon already exists for `oc-smart` on port 43516 (`~/.ccs/proxy/`),
apparently auto-started at profile creation. Its `baseUrl` is the stale `/zen`
and it will need restarting after the config fix.

**Do not deploy the Cloudflare Worker** from
`github.com/cucoleadan/opencode-cowork-proxy`. It solves exactly the problem
`ccs proxy` already solves locally, while routing every request and the API key
through third-party infrastructure.

### Other settled facts

- **Zen BYOK is limited to OpenAI and Anthropic keys.** The user's DeepSeek key
  cannot be attached to the opencode workspace; `deepseek` stays a separate
  `ccs` profile.
- **go has no Claude and no Gemini.** Only `gpt-5.6-luna`, which 500s. `agy`
  is therefore *not* redundant and remains the only frontier/research path.
  PAYG Zen does list `claude-opus-5` / `gemini-3.1-pro`, but reaching them
  means funding Zen credits on top of the go subscription — rejected.
- Installed: `ccs` v8.9.0 (`~/.npm-global/bin/ccs`), `agy` (`~/.local/bin/agy`).
  **opencode is not installed and is deliberately not being installed.**
- Cost reference (per Mtok, from `~/.ccs/models-dev-registry-cache.json`):
  `deepseek-v4-flash` 0.14/0.28 · `deepseek-v4-pro` 0.44–1.74/0.87–3.48 ·
  `kimi-k3` 3/15. go is flat-rate ($10/mo, **$60 monthly usage cap**), so these
  do not hit the wallet directly — they determine **how fast the cap burns**.
  `kimi-k3` burns it 4–8× faster than `deepseek-v4-pro`.

## Target profile set (final)

| Profile | Transport | Endpoint | Model | Role |
|---|---|---|---|---|
| `oc-fast` | direct | `opencode.ai/zen/go` | `deepseek-v4-flash` | mechanical edits, cheapest |
| `oc-smart` | direct | `opencode.ai/zen/go` | `deepseek-v4-pro` | **default** coding reach |
| `oc-max` | direct | `opencode.ai/zen/go` | `qwen3.8-max` | harder OSS reasoning, before Claude quota |
| `oc-free` | **`ccs proxy`** | `opencode.ai/zen` | `mimo-v2.5-free` | playground/throwaway |
| `deepseek` | direct | `api.deepseek.com/anthropic` | `deepseek-v4-pro[1m]` | **overflow** when the $60 go cap hits |
| `agy-gemini` | agy | — | `gemini-3.1-pro-high` | research (not coding) |
| `agy-opus` | agy | — | `claude-opus-4-6-thinking` | frontier coding escape, worth-it only |

**Dropped:** `agy-flash`, `agy-oss`, `agy-sonnet`, the `nvidia` ccs profile, and
`grok-4.6` (unavailable).

**Two transports, deliberately mixed.** The paid `oc-*` profiles go direct — no
daemon to supervise for the common path. `oc-free` is the only profile that
*requires* the local proxy, because free models exist only in Anthropic-hostile
form. Route B was verified production-viable (tool calls + streaming), so
switching everything to it later is a safe option if uniformity becomes worth
the daemon lifecycle cost.

### Open items to resolve during implementation

- **`oc-max` is unvalidated.** `qwen3.8-max` was chosen because it works
  natively and is newer than the `qwen3.7-max` in the grill-time ordering
  (`Grok 4.6 ≳ DeepSeek V4 Pro > Qwen 3.7 Max ≈ Kimi K3 > GLM 5.2`). By that
  ordering, with grok gone, **nothing available clearly beats `deepseek-v4-pro`
  — meaning `oc-max` may be a tier with nothing above `oc-smart` in it.**
  A/B it against `oc-smart` on a real task before documenting it as an
  escalation. If it does not beat `oc-smart`, delete the tier and escalate
  `oc-smart → agy-opus`.
- **go's DeepSeek context window is unmeasured.** `[1m]` is rejected on go;
  DeepSeek's own registry lists ~1M for the base model, but opencode may serve
  a smaller window. Do not document a long-context claim for `oc-smart` until
  measured. The `deepseek` PAYG profile keeps `[1m]` and is scoped as **cap
  overflow only** — drop any long-context framing.

## Routing logic (flat — replaces the shared-quota essay)

1. Default coding → `oc-smart`.
2. Small mechanical, fast turnaround → `oc-fast`.
3. Reasoning harder than `oc-smart` handles, still OSS-appropriate → `oc-max`.
4. go's $60 cap hit → `deepseek` (PAYG overflow).
5. Task genuinely needs Claude's judgment, worth the tighter agy quota → `agy-opus`.
6. Research (not coding) → `agy-gemini`.
7. Not worth orchestrating, or agy absent → **the orchestrator does it inline.**
8. Just playing / throwaway → `oc-free`.

Mixing profiles across a fan-out is still good practice. Only fan out genuinely
independent tasks; serialize tasks that share a file.

## Work order

Do these in sequence. Steps 1–3 are the actual bug fix; the rest is the rework.

### 1. Fix the profiles (`~/.ccs/*.settings.json`)
- `oc-fast`, `oc-smart`, `oc-max`: `ANTHROPIC_BASE_URL` → `https://opencode.ai/zen/go`.
- Set `ANTHROPIC_MODEL` (and the OPUS/SONNET/HAIKU mirrors) per the table.
- `oc-free`: base URL stays `https://opencode.ai/zen`, model `mimo-v2.5-free`,
  keep `CCS_DROID_PROVIDER: generic-chat-completion-api`.
- Restart the stale `oc-smart` proxy daemon (port 43516) so it stops pointing
  at `/zen`.
- `fleet-update` should be able to write these via `ccs api`, so a new machine
  is one command.

### 2. `scripts/ccs-fleet.sh` — fail-fast preflight
A dead profile currently costs 118s and reports the wrong reason. Before
launching, probe the profile (a `/v1/models` call, or one 24-token message) and
on failure **die in ~2s printing the raw upstream `error.message`**.
`CreditsError: Insufficient balance` and `RegionError: requires explicit opt in`
are both directly actionable; the retry loop is what destroyed that signal.

### 3. `scripts/ccs-fleet.sh` — routing and transports
- `tool_for_profile`: `oc-fast|oc-smart|oc-max|oc-free|deepseek → ccs`;
  `agy-gemini|agy-opus → agy`. Remove all old profile names.
- `agy_default_model`: only `agy-gemini → gemini-3.1-pro-high`,
  `agy-opus → claude-opus-4-6-thinking`. Delete flash/pro/oss/sonnet.
- **`oc-free` needs proxy lifecycle**: start the `ccs proxy` daemon if absent,
  health-check it, and tear it down. This is a new failure mode inside
  worktrees — handle a dead or port-conflicted daemon explicitly.
- **Graceful agy absence**: if the profile is `agy-*` and `command -v agy`
  fails, die with a clear message telling the user to run the task in the
  orchestrator instead.
- No opencode-binary branch anywhere. `oc-*` are plain `ccs <profile> -p`.
- Update usage/help text.

### 4. `ccs-fleet-update` — add `--verify`
Probe every profile, report the real upstream error per model, and flag drift
(e.g. `[1m]` invalid on go, a base URL that isn't `/zen/go`, a free id that
now 404s). **This would have caught the bug in seconds instead of costing a
full grilling session and a wrong architectural conclusion.**

### 5. `SKILL.md`
- Rewrite around the new model; drop the GPT-OSS / Sonnet / Opus shared-quota
  prose entirely. Replace the routing table with the flat 8-point logic.
- **State that the `oc-*` DeepSeek profiles are China-hosted.**
- State that `oc-free`'s model id is volatile, swappable via `--model`, and
  that free models may log data for training — never for real work.
- Keep the CCS output-quirk warnings (fabricated `Cost`, `unrecognized_model`,
  `claude.ai connectors are disabled`) — they now apply to all `oc-*` and
  `deepseek` runs.
- Shrink the agy JSON-output section to `agy-gemini`/`agy-opus`, and state that
  agy is optional and the fleet degrades to the orchestrator without it.
- **Trim aggressively** — the file is ~15KB and the orchestrator re-reads it.

### 6. `references/mechanics.md`
- Document the `/zen` vs `/zen/go` distinction and the per-model format table.
- Document `ccs proxy` as the local Anthropic→OpenAI bridge, and explicitly say
  the Cloudflare Worker is unnecessary, so nobody re-derives it.
- Record the go subscription's $10/mo, $60 cap, and the China-hosting opt-in.

### 7. `evals/evals.json`
1. fanout-three-chores → lands on `oc-*` profiles.
2. single-vague-brief → `oc-smart`.
3. shared-file-serialization → unchanged intent.
4. hard-refactor → `oc-max`, **not** agy; choice ties to "don't spend Claude quota".
5. NEW: go-cap-exhausted → re-routes to `deepseek` PAYG overflow.

### 8. Rename — **separate commit, afterwards**
`ccs-fleet` → `fleet`, `ccs-fleet-update` → `fleet-update`. Keep the
`CCS_FLEET_*` env var names (internal; bounds blast radius). Update the skill
dir/symlink, both install locations, `evals.json` skill_name, descriptions and
triggers, and cross-references between the two skills. Doing this after the
content work keeps the real diff readable.

## Verification before done

- Each `oc-*` profile resolves and `ccs oc-smart -p "print hello"` returns in
  seconds, not 118.
- A deliberately broken profile fails in ~2s with the true upstream message.
- `oc-free` completes a **tool-using** task end-to-end through `ccs proxy`.
- `scripts/*.sh launch --profile oc-smart ...` runs end-to-end in a worktree.
- `agy-opus`/`agy-gemini` launch (agy present) **or** degrade cleanly (agy absent).
- `oc-max` A/B'd against `oc-smart` — keep or delete the tier on the result.
- Run the eval suite via the skill-creator/eval tooling.

## Corrections to the previous handoff

Both of its load-bearing premises were wrong. Recorded so they are not
re-derived:

1. **"The decisive fact: opencode Zen exposes an Anthropic-compatible endpoint,
   so ccs points at it exactly like DeepSeek."** Only partly true — the
   Anthropic adapter covers 6 of 32 go models, and *zero* free models. The
   architecture is not identical to the DeepSeek profile.
2. **It never knew `/zen/go` existed**, and pointed every profile at the
   unfunded PAYG endpoint. This, not architecture, is what broke the fleet.

Also superseded: `grok-4.6` for `oc-max` (unavailable in any format);
`oc-free` as a plain `ccs` API profile (it requires `ccs proxy`); and the
implication that opencode could replace `agy` for frontier work (go serves no
Claude and no Gemini).
