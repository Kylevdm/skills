---
name: ccs-fleet-update
description: >-
  Update the ccs-fleet skill itself — add, remove, or rename a `ccs`/`agy`
  profile, change which model a profile defaults to, or rebalance the
  routing table when pricing/quota changes (e.g. "a new model showed up in
  agy", "add gpt-oss to the fleet", "stop defaulting to sonnet/opus, they
  have a separate usage limit", "nvidia's free tier changed", "rename this
  profile", "the routing table is out of date"). Use this whenever the user
  wants the ccs-fleet skill's config changed rather than run — this is the
  maintenance skill for that skill. Always use this instead of hand-editing
  ccs-fleet's files directly: it keeps the four touchpoints (script,
  SKILL.md, mechanics.md, evals) and the two install locations in sync,
  which is easy to half-do by hand.
---

# CCS Fleet Update

Keep the [ccs-fleet](../ccs-fleet/SKILL.md) skill's profile/model config
current. That skill routes work to `ccs` and `agy` backends; this skill is
how you change *what* it routes to, safely and completely — the whole risk
here is editing one of four touchpoints and forgetting the other three, or
editing the repo copy and forgetting the skill only actually runs from the
installed copy (or vice versa).

## Where things live

Two directories that should be byte-identical, because they are not
symlinked on this machine — check with `diff -rq` before you assume:

- Repo (source of truth, under version control): `~/Development/skills/ccs-fleet/`
- Installed (what Claude Code actually loads): `~/.claude/skills/ccs-fleet/`

Four files inside make up the config surface:

| File | What lives there |
|---|---|
| `scripts/ccs-fleet.sh` | `tool_for_profile()` (profile → ccs/agy), `agy_default_model()` (profile → model id), the usage/help text at the bottom |
| `SKILL.md` | frontmatter description (profile list + keywords), intro paragraph, the routing table + the prose around it, the `agy`/`ccs` example commands |
| `references/mechanics.md` | verified CLI behavior — only touch this when you've verified something new about a model/profile, not for routing preference changes |
| `evals/evals.json` | regression prompts; add one when a routing *preference* changes, so a future skill edit can't silently undo it |

## Before touching anything: verify, don't guess

A model id typed from memory is a coin flip. Confirm it against the actual
tool before it goes in the script:

```bash
agy models                       # lists agy's current model ids + display names
cat ~/.ccs/config.yaml           # ccs profiles (nvidia, deepseek, ...) and their settings files
```

If the user names a model casually ("gpt-oss", "the new gemini flash"), match
it against what `agy models` actually prints — the id in the script must be
the exact slug (e.g. `gpt-oss-120b-medium`, not `gpt-oss-120b`).

## Making the change

1. **Script first** (`scripts/ccs-fleet.sh`) — it's the only place that's
   load-bearing at runtime; SKILL.md is guidance text that can drift without
   breaking anything, but a wrong profile id here fails every launch.
   - New profile: add to `tool_for_profile()`'s case statement (which
     backend), `agy_default_model()` if it's an agy profile (the model id
     from `agy models`), and the `die`/usage-text profile lists.
   - Rebalance only (no new profile): script usually doesn't change — this
     is a SKILL.md-only edit.
   - Removed/renamed profile: grep the whole skill directory for the old
     name before considering it done; a stale reference in prose is a worse
     failure mode than a stale reference in code, because nothing errors on
     it.

2. **SKILL.md** — update in this order, since each layer references the last:
   - Frontmatter `description`: the profile/model list and the trigger
     keywords (model nicknames people actually type — "gpt-oss", "flash",
     "nemotron").
   - Intro paragraph: same list, prose form.
   - The routing table: this is the part that actually shapes behavior —
     it's what Claude reads to pick a profile. State *why* a profile is the
     right pick for its task shape, not just its name; that's what lets
     future-you (or future-Claude) judge edge cases the table doesn't
     enumerate. If the change is "reduce reliance on X", the lever is the
     prose immediately after the table, not just moving X's row — say
     explicitly what to reach for first and why the alternative costs more
     (a separate quota, real billing, worse fit for the task shape).
   - The `Running a fleet` example commands: keep them consistent with the
     routing guidance you just wrote — an example that contradicts the
     table it sits below undermines both.

3. **references/mechanics.md** — only if you learned something concrete
   about the new/changed model's behavior while testing (see below). Don't
   speculate here; every claim in that file is written as "verified on
   <date>" for a reason — someone will trust it literally.

4. **evals/evals.json** — add a prompt when the *routing preference*
   changed (not the profile list). A good one names the task shape and the
   constraint that should drive the choice (cost, quota, task difficulty),
   and its `expected_output` states which profile should win and why — see
   the existing entries for the pattern.

## Smoke-test before calling it done

A profile that parses correctly can still fail at runtime — wrong model id,
wrong trust dir, a model that narrates a tool call it never made. Launch one
real agent against a disposable repo and confirm the diff actually lands:

```bash
D=$(mktemp -d)
cd "$D" && git init -q && git commit -q --allow-empty -m init
echo hello > README.md && git add README.md && git commit -q -m readme

CCS_FLEET_HOME="$D/.fleet" ~/Development/skills/ccs-fleet/scripts/ccs-fleet.sh \
  launch --task smoke --profile <new-or-changed-profile> --repo "$D" \
  --prompt "Append the line 'smoke-test-ok' to README.md using your file-editing tool, then confirm you saved it."

# poll: agy runs finish in ~10-20s, ccs-backed profiles can take longer
CCS_FLEET_HOME="$D/.fleet" ~/Development/skills/ccs-fleet/scripts/ccs-fleet.sh status --repo "$D"
CCS_FLEET_HOME="$D/.fleet" ~/Development/skills/ccs-fleet/scripts/ccs-fleet.sh diff smoke   # run from inside $D
```

Look for a non-empty diff, not just `status: SUCCESS` — a `done` agent with
`0 file(s)` changed means it talked about editing without doing it (verified
behavior on `agy-oss`, worth checking on any new agy model too). Clean up
after: `ccs-fleet.sh clean smoke --force`, then `rm -rf "$D"`.

## Sync and verify

The two directories only match because you make them match. After editing
the repo copy:

```bash
rsync -a --delete ~/Development/skills/ccs-fleet/ ~/.claude/skills/ccs-fleet/
diff -rq ~/Development/skills/ccs-fleet ~/.claude/skills/ccs-fleet && echo "in sync"
```

Do this last, after the smoke test passes against the repo copy — no point
syncing a config you're about to revise again.

## Reporting back

Tell the user, concretely: which file(s) changed and why, what the new
routing guidance says to reach for and what it now avoids, and what the
smoke test showed (profile, model id, and that a real diff landed — not just
an exit code). If you skipped the smoke test because the change was
prose-only (no script edit, no new profile), say so rather than silently
omitting it.
