# Fog ledger

Fog is the dim view ahead of an active map: in-scope areas you can tell are coming but cannot yet phrase sharply enough to ticket. The map's **Not yet specified** section is the store for active-map fog. This ledger is the live index across maps and sessions.

Last swept: Never.

## Where to put things

| It is… | It goes… |
| --- | --- |
| Unsharp and in scope for an active map | That map's **Not yet specified** |
| Sharp enough to state as a question | A ticket on its map, even if blocked |
| Already decided | The map's **Decisions so far**, linking the resolution |
| Past one map's destination but wanted and owned by no current map | **Deferred efforts** |
| Conditional, within a closing map's destination, unowned, and not triggered | Mark **CARRIED** on the map and index it under **Carried** |
| A random wanted idea with no source map or owner | **Deferred efforts** |

Closing a map requires marking every patch in **Not yet specified**:

- **ANSWERED** — current evidence resolved it; state and link the answer.
- **REHOMED** — another map, ticket, or scope owns it; link the owner.
- **CARRIED** — still within the destination, still unowned, and its trigger did not fire; preserve the human's rationale and index it below.

A patch that blocks the destination prevents closure. Work explicitly beyond the destination is never Carried.

Every live row states what it is, cites where it touches the build when applicable, and names the observable event that makes it ready for owned work. `Trigger: none yet` is valid.

## Carried

Live conditional fog from closed maps, grouped by the map that raised it.

<!--
### From [Map title](map link) (closed)

| Patch | Trigger |
| --- | --- |
| What remains unknown, with evidence such as `path:line` or a linked issue | Observable trigger, or none yet |
-->

## Triaged

Closed maps whose **Not yet specified** patches are all marked. Record maps with zero patches too.

<!-- - [Map title](map link) — triaged YYYY-MM-DD: 0 ANSWERED, 0 REHOMED, 0 CARRIED. -->

## Deferred efforts

Wanted work outside every current map's destination and owned by nobody. An idea that never came from a map belongs here too. Group into subject subsections once there are enough entries to scan; other entries then refer to them by name.

### Fleet / Pi migration follow-ups

- **Evaluate local Ollama models for Fleet's economy tier.** There is no current
  Fleet/Ollama integration; Fleet's active harness and routing are Pi/provider
  based (`fleet/scripts/fleet.sh`). Keep local models out of the initial redesign
  so the first evaluation measures the approved OpenCode Go and direct DeepSeek
  pool. Trigger: after the first evidence-backed routing review if economy-tier
  acceptance is poor, or sooner if the Go monthly allowance becomes a
  constraint.

- **Evaluate containerized Fleet workers for stronger isolation.** The initial
  redesign retains Pi's launching-user filesystem access and uses worktrees only
  for Git isolation (`fleet/CONTEXT.md`, **Worktree quarantine**;
  `fleet/references/mcp-control-design.md`, **Security boundary**). Environment
  sanitization and provider privacy rules reduce exposure but are not a process
  security boundary. Trigger: Fleet must run against a repository that cannot
  safely be exposed to an approved provider, or a security review requires
  filesystem, credential, or network isolation.

- **Wire `pi-deepseek` to a real, separately-billed DeepSeek API key/profile in `fleet.sh`.** Today it routes through `opencode-go/deepseek-v4-pro` (`fleet/scripts/fleet.sh` `fleet_profiles()`, ~line 56) and shares the same $60/mo go cap as `pi-default`/`pi-plus` — it is not an overflow path. `fleet/references/mechanics.md`'s `CreditsError` row and `fleet/evals/evals.json` scenario 5 (`go-cap-exhausted-overflow`) are both written assuming this repoint has already happened; scenario 5 carries an inline `note` field saying so and will read as a false positive/negative until the change lands. This is the user's own action item, expected shortly ("I will add deepseek api to pi after this grilling"). Trigger: `pi-deepseek` repointed to a standalone DeepSeek API key — at that point, update `fleet.sh`, `fleet/SKILL.md`'s profile table and ADR 0002, remove evals.json scenario 5's caveat note, and re-verify the scenario against the real behavior.

- **Migrate `fleet-update/SKILL.md` off ccs/agy to Pi.** It still describes the retired ccs/agy harness end to end — `ccs api list`, `agy models`, `CCS_DROID_PROVIDER`, `~/.ccs/*.settings.json`, `$F provision` — none of which exist in the Pi-era fleet (`fleet/scripts/fleet.sh`, `fleet/SKILL.md`, `fleet/references/mechanics.md`, all rewritten 2026-09-08; `fleet-update/SKILL.md` was not touched in that pass). Needs the same shape of rewrite the fleet skill itself just got: script table, routing prose, mechanics.md conventions, evals, all re-derived for Pi/opencode-go. Once migrated, it should carry a standing check — run whenever a profile is added or changed — confirming the model's training/retention terms before it's wired into `fleet.sh`'s routing table, per the corrected framing in `fleet/SKILL.md`'s "The go profiles route code to China-hosted inference" section (2026-09-08): the live constraint is data training/retention, not hosting geography, and models known to train on submitted data are excluded at the opencode workspace/account level, not by routing logic. Trigger: none yet — raise this the next time `fleet-update` is actually invoked to change the fleet's profile table, since at that point the skill's staleness becomes load-bearing rather than latent.
