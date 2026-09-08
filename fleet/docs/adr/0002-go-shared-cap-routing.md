# Route fleet coding through the opencode go shared-cap pool; deepseek-v4-pro is default-off

---
status: accepted
---

Fleet coding now runs on **opencode go** models billed against the
subscription's shared **$60 monthly cap** (one pot across all go models, at
each model's list price). **deepseek-v4-pro** — the fleet's former default and
the only model validated so far — remains available but is used only when the
user expressly requests it. The rest of the go pool is newly reachable (Pi's
OpenAI-native access removed the per-model Anthropic-adapter exclusions) but
none of it has been validated as a coding agent, so the default routing will be
chosen by A/B rather than assumed.

## Considered Options

- **deepseek-v4-pro stays the default**: rejected — the user wants it reserved
  for explicit requests, and the newly reachable pool explored on its merits.
- **Pick defaults from capability guesses**: rejected — price is a poor proxy
  for coding ability and most of the pool has no evidence behind it.
- **A/B the pool, with deepseek-v4-pro as the control baseline**: chosen.
  Defaults are promoted only when they match or beat the control on the same
  defined ticket, with cap burn as the tie-breaker.

## Consequences

- Deepseek-v4-pro is the yardstick, not the workhorse: it grades the pool
  during evaluation and answers explicit user requests afterwards.
- Burn-rate is a routing input because the cap is shared; a model that matches
  the control at a fraction of the burn-rate is the better default.
- Defaults are provisional until the evaluation run lands; the fleet skill's
  routing table records them and the evidence that earned them.
