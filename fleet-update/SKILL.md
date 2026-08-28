---
name: fleet-update
description: >-
  Update the fleet skill itself — add, remove, or rename a `ccs`/`agy`
  profile, change which model a profile defaults to, repoint a profile at a
  different endpoint, or rebalance the routing order when pricing/quota
  changes (e.g. "the oc-free model id is dead again", "add a profile for the
  new opencode model", "we hit the monthly cap, make deepseek the default",
  "grok is available again", "the routing list is out of date"). Use this
  whenever the user wants the fleet skill's config changed rather than
  run — this is the maintenance skill for that skill. Always use this instead
  of hand-editing fleet's files directly: it keeps the profile table, the
  routing prose, mechanics.md, and the evals in sync, and it starts by
  probing the live endpoints so a change is never made against a guess.
---

# CCS Fleet Update

Keep the [fleet](../fleet/SKILL.md) skill's profile/model config
current. That skill routes work to `ccs` and `agy` backends; this skill is
how you change *what* it routes to, safely and completely.

## Start by probing, never by guessing

Model ids and endpoints churn constantly here — opencode's free ids rot
within days, and its Anthropic-format support is per-model and server-side.
So the first move on any change is always:

```bash
F=~/.claude/skills/fleet/scripts/fleet.sh
$F verify                        # every profile: live probe + config drift
agy models                       # agy's current ids and display names (agy profiles only)
ccs api list                     # which ccs profiles are registered at all
```

`verify` sends each profile a real 24-token completion and prints the
provider's own error. That matters more than it sounds: the outage this
command was written for served `/v1/models` a clean 200 and only failed on
generation, so a listing endpoint is not evidence a profile works.

When adding or repointing a profile, probe the *specific model* before it
goes in the table — opencode's Anthropic adapter covers only 6 of its 33 `go`
models, and a model that answers `/chat/completions` fine will 500 on
`/v1/messages`:

```bash
K=$(python3 -c 'import json;print(json.load(open("'"$HOME"'/.ccs/oc-fast.settings.json"))["env"]["ANTHROPIC_API_KEY"])')
curl -s -m 30 -H "x-api-key: $K" -H "content-type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"<id>","max_tokens":24,"messages":[{"role":"user","content":"say ok"}]}' \
  https://opencode.ai/zen/go/v1/messages
```

A 500 there means the model needs the OpenAI path instead, which means its
profile needs `CCS_DROID_PROVIDER: generic-chat-completion-api` — see
`references/mechanics.md` for why that one field decides the whole transport.

## Where things live

Check before assuming, because this differs per machine:

```bash
readlink -f ~/.claude/skills/fleet
```

On this machine `~/.claude/skills/fleet` is a **symlink** to
`~/Development/skills/fleet`, so the repo copy *is* the installed copy and
there is nothing to sync. If `readlink -f` ever comes back as a real directory
of its own, the two are independent copies and every edit needs an
`rsync -a --delete ~/Development/skills/fleet/ ~/.claude/skills/fleet/`
afterwards, plus a `diff -rq` to confirm. Do not run that rsync blind — onto a
symlink it is a no-op at best.

Four files make up the config surface:

| File | What lives there |
|---|---|
| `scripts/fleet.sh` | `fleet_profiles()` — the one table of name/tool/endpoint/model/transport that `launch`, `verify`, and `provision` all read — plus the usage text at the bottom |
| `SKILL.md` | frontmatter description (profile list + keywords), intro, the numbered routing list, the example commands |
| `references/mechanics.md` | verified endpoint and CLI behaviour — only touch when you have *verified* something new, not for routing preference changes |
| `evals/evals.json` | regression prompts; add one when a routing *preference* changes, so a future edit can't silently undo it |

## Making the change

1. **`fleet_profiles()` in the script first.** It is the only load-bearing
   place: a wrong entry fails every launch, whereas SKILL.md is guidance that
   degrades quietly. One row per profile,
   `name|tool|base-url|model|transport`. For agy rows only the model column
   is meaningful (`-` for the rest); the id must be the exact slug from `agy
   models`. Adding or removing a row updates `tool_for_profile`,
   `agy_default_model`, `verify`, and `provision` at once — but the usage
   text at the bottom of the script is written by hand, so update it too.

   `transport` is `anthropic` for a profile that talks to the upstream
   directly, and `generic-chat-completion-api` for one that has to go through
   ccs's local Anthropic→OpenAI proxy. ccs starts and owns that daemon
   itself; the script must never manage it.

2. **The live `~/.ccs/*.settings.json`.** The script's table is what the
   fleet *expects*; the settings files are what ccs actually reads. Change
   both or `verify` will report drift. `$F provision` rewrites every ccs
   profile from the table (needs `OPENCODE_API_KEY`, and `DEEPSEEK_API_KEY`
   for the deepseek profile) — that is also how a new machine gets set up in
   one command. Note that `ccs api create` writes
   `CCS_DROID_PROVIDER: generic-chat-completion-api` for any base URL it does
   not recognise, so a hand-run `ccs api create` needs that field corrected
   afterwards; `provision` already does.

3. **SKILL.md**, in this order, since each layer references the last:
   - Frontmatter `description`: the profile list and the trigger keywords
     people actually type ("opencode", "zen", "qwen", "opus").
   - Intro paragraph: same list, prose form.
   - The numbered routing list: this is what actually shapes behaviour. Each
     entry names a task shape and the reason that profile fits it — keep the
     reason, since that is what lets a future reader judge the cases the list
     doesn't enumerate. To reduce reliance on a profile, the lever is its
     stated reason and its position in the order, not just deleting the row.
   - The example commands: an example that contradicts the routing list
     undermines both.

4. **`references/mechanics.md`** — only when you verified something concrete.
   Every claim there is dated for a reason; someone will trust it literally.

5. **`evals/evals.json`** — add a prompt when the routing *preference*
   changed. A good one names the task shape and the constraint that should
   drive the choice, and its `expected_output` states which profile should win
   and why.

## Smoke-test before calling it done

A profile that verifies can still fail at runtime — a model that narrates a
tool call it never made, or one that can't hold a multi-step edit together.
Launch one real agent against a disposable repo and confirm the diff lands:

```bash
D=$(mktemp -d)
git -C "$D" init -q && echo hello > "$D/README.md"
git -C "$D" add -A && git -C "$D" -c user.email=t@t -c user.name=t commit -q -m init

export CCS_FLEET_HOME="$D/.fleet"
$F launch --task smoke --profile <new-or-changed-profile> --repo "$D" \
  --prompt "Append the line 'smoke-test-ok' to README.md using your file-editing tool, then confirm you saved it."

$F status --repo "$D"
(cd "$D" && $F diff smoke)
```

Look for a non-empty diff, not just exit 0 — a `done` agent with `0 file(s)`
changed means it talked about editing without doing it. Clean up after:
`$F clean smoke --force`, then `rm -rf "$D"`.

If the change was a *routing preference* rather than a new profile, the
smoke test proves nothing; run `evals/evals.json` instead — those prompts
exist to catch a routing preference being silently undone.

If you touched the frontmatter `description`, re-run `evals/trigger-evals.json`
as well, and read that file's `_readme` first: skill-creator's
`scripts/run_eval.py` **cannot score this skill**. It installs a throwaway copy
of the description as `fleet-skill-<uuid>` and counts only that name, so with
the real `fleet` skill installed Claude invokes `fleet` and every true positive
reads as a miss. Count `Skill(skill="fleet")` anywhere in the transcript
instead. `scripts/quick_validate.py <skill-path>` is worth running either way —
it catches an over-long description (1024 char limit) and angle brackets, both
of which this skill has tripped over.

## Reporting back

Tell the user, concretely: which files changed and why, what the routing now
says to reach for first and what it now avoids, and what `verify` plus the
smoke test actually showed — profile, model id, and that a real diff landed,
not just an exit code. If you skipped the smoke test because the change was
prose-only, say so rather than silently omitting it.
