# Adopt Pi as the fleet's delegated-agent harness

---
status: accepted
---

The fleet delegated agents through **ccs**, which stood up headless Claude Code
per provider profile. We are moving to **Pi** (pi.dev) as the harness, keeping
the fleet script's worktree orchestration and the human review-and-land gate
unchanged, and retiring ccs. ccs was fragile to reproduce on a new machine
(config.yaml, per-profile settings files, `CCS_DROID_PROVIDER` drift, a local
proxy daemon) and it ran Claude Code's interactive plugins and skills inside
every headless agent where they were inert; agy, the other delivery path, fails
mid-delivery too often to trust.

## Considered Options

- **Keep ccs / headless Claude Code**: per-machine setup drifts and is hard to
  reproduce; the interactive harness weight is pointless in headless agents.
- **agy (Antigravity)**: regularly fails halfway through delivery; retained
  only as an independent app for research and frontier reach, outside the
  delivery fleet.
- **Pi (pi.dev)**: MIT, actively maintained (100k+ GitHub stars, multi-million
  weekly npm installs), natively speaks the opencode-go and DeepSeek endpoints,
  is headless-safe (`pi -p`, `--mode json`, `--mode rpc`), reads a repo's
  CLAUDE.md/AGENTS.md so briefs transfer, and never auto-commits. Chosen.

## Consequences

- Pi has no permission prompts — it acts as the launching user. The worktree
  quarantine and the review gate are the safety model, exactly as they were.
- Pi never auto-commits or branches; the fleet script keeps the git lifecycle
  (`land`, `clean`, `resume`) it already owns.
- A new machine needs one Pi install plus a provider key — no ccs profile zoo.
- Pi is young and ships breaking changes quickly; pin the installed version.
- Pi talks to opencode go natively (OpenAI-format), removing the
  Anthropic-adapter path that previously made some go models unreachable.
