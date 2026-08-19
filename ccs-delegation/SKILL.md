---
name: ccs-delegation
description: >-
  Auto-activate CCS CLI delegation for deterministic tasks. Parses user input,
  auto-selects optimal profile (glm/kimi/custom) from ~/.ccs/config.json,
  frames every delegated task as an /implement run (TDD at seams, typecheck,
  full suite, commit) per the mattpocock implement skill, executes via
  `ccs {profile} -p "task"` or `ccs {profile}:continue`, then the orchestrating
  session — not the delegated model — runs code-review against the result.
  Triggers on "use ccs [task]" patterns, typo/test/refactor keywords. Excludes
  complex architecture, security-critical code, performance optimization,
  breaking changes.
version: 5.0.0
---

# CCS Delegation

Delegate implementation *labor* — not judgment — to cost-optimized models via
CCS CLI. This skill is `/implement`, fleet-routed: the build discipline is
always the mattpocock `implement` playbook (see Implementation Framework
below); CCS decides which model does the code-bashing, but review is never
delegated. The orchestrating session (you) always reviews the delegated
model's own work — a model reviewing itself is prone to missing its own
mistakes and rubber-stamping its own approach, so that check has to come from
outside.

## Core Concept

Execute tasks via alternative models using:
- **Initial delegation**: `ccs {profile} -p "task"`
- **Session continuation**: `ccs {profile}:continue -p "follow-up"`

**Profile Selection:**
- Auto-select from `~/.ccs/config.json` via task analysis
- Profiles: glm (cost-optimized), kimi (long-context/reasoning), custom profiles
- Override: `--{profile}` flag forces specific profile

## User Invocation Patterns

Users trigger delegation naturally:
- "use ccs [task]" - Auto-select best profile
- "use ccs --glm [task]" - Force GLM profile
- "use ccs --kimi [task]" - Force Kimi profile
- "use ccs:continue [task]" - Continue last session

**Examples:**
- "use ccs to fix typos in README.md"
- "use ccs to analyze the entire architecture"
- "use ccs --glm to add unit tests"
- "use ccs:continue to commit the changes"

## Implementation Framework

Every delegated task, whatever profile ends up running it, is framed as an
`/implement` run before it goes over the wire — with the review beat carved
out and kept local:

**Delegated (the model does this):**
1. Read the ticket/spec/conversation plan and work out the seams.
2. Drive TDD at pre-agreed seams — red, green, one slice at a time.
3. Typecheck often; run single test files as it goes.
4. Run the full test suite once, at the end.
5. Commit to the current branch.

**Never delegated (you do this, after step 6 in the protocol below):**
6. Run code-review yourself against the delegated commit, and act on what it
   finds — fix directly, or send a follow-up delegation for anything
   substantial.

This split is not re-litigated per delegation — it's the fixed harness the
enhanced prompt is built from. Do not ask the delegated task to "just write
the code"; ask it to run beats 1-5. Do not ask it to review its own work
either — omit that instruction entirely, since a model grading its own diff
tends to miss what it got wrong. `/implement` never reopens the plan (no
interview, no redesign) — neither does a delegated run. Whatever was settled
upstream (ticket, spec, or the conversation you just had) is the input; the
delegated model's job is to turn it into a commit, and your job is to check
that commit before calling the task done.

## Agent Response Protocol

**For `/ccs [task]`:**

1. **Parse override flag**
   - Scan task for pattern: `--(\w+)`
   - If match: `profile = match[1]`, remove flag from task, skip to step 5
   - If no match: continue to step 2

2. **Discover profiles**
   - Read `~/.ccs/config.json` using Read tool
   - Extract `Object.keys(config.profiles)` → `availableProfiles[]`
   - If file missing → Error: "CCS not configured. Run: ccs doctor"
   - If empty → Error: "No profiles in config.json"

3. **Analyze task requirements**
   - Scan task for keywords:
     - `/(think|analyze|reason|debug|investigate|evaluate)/i` → `needsReasoning = true`
     - `/(architecture|entire|all files|codebase|analyze all)/i` → `needsLongContext = true`
     - `/(typo|test|refactor|update|fix)/i` → `preferCostOptimized = true`

4. **Select profile**
   - For each profile in `availableProfiles`: classify by name pattern (see Profile Characteristic Inference table)
   - If `needsReasoning`: filter profiles where `reasoning=true` → prefer kimi
   - Else if `needsLongContext`: filter profiles where `context=long` → prefer kimi
   - Else: filter profiles where `cost=low` → prefer glm
   - `selectedProfile = filteredProfiles[0]`
   - If `filteredProfiles.length === 0`: fallback to `glm` if exists, else first available
   - If no profiles: Error

5. **Enhance prompt**
   - If task mentions files: gather context using Read tool
   - Add: file paths, current implementation, expected behavior, success criteria
   - Wrap the task in the Implementation Framework's delegated beats
     (1-5 only): instruct the run to find the seams, TDD at them, typecheck
     as it goes, run the full suite once, and commit to the current branch —
     don't just hand over the bare task string, and don't ask it to review
     its own work; that step is yours
   - Preserve slash commands at task start (e.g., `/cook`, `/commit`)

6. **Execute delegation**
   - Run: `ccs {selectedProfile} -p "$enhancedPrompt"` via Bash tool

7. **Review (never delegated)**
   - Once the delegation returns, run `/code-review` yourself against the
     commit(s) it produced — don't take the delegated model's word that it's
     done
   - Act on findings: fix directly for small stuff, or send a follow-up
     `ccs {profile}:continue` delegation for anything substantial
   - Only report the task complete once your review has passed

8. **Report results**
   - Log: "Selected {profile} (reason: {reasoning/long-context/cost-optimized})"
   - Report: Cost (USD), Duration (sec), Session ID, Exit code, and your
     review verdict (clean / fixed locally / sent back for rework)

**For `/ccs:continue [follow-up]`:**

1. **Detect profile**
   - Read `~/.ccs/delegation-sessions.json` using Read tool
   - Find most recent session (latest timestamp)
   - Extract profile name from session data
   - If no sessions → Error: "No previous delegation. Use /ccs first"

2. **Parse override flag**
   - Scan follow-up for pattern: `--(\w+)`
   - If match: `profile = match[1]`, remove flag from follow-up, log profile switch
   - If no match: use detected profile from step 1

3. **Enhance prompt**
   - Review previous work (check what was accomplished)
   - Add: previous context, incomplete tasks, validation criteria
   - Re-anchor on the Implementation Framework's delegated beats: if the prior
     run left TDD slices, typechecks, the full suite, or the commit
     unfinished, resume at that beat rather than restarting from scratch. If
     this continuation exists because your review sent work back, state the
     specific findings to fix — don't just say "address the review"
   - Preserve slash commands at start

4. **Execute continuation**
   - Run: `ccs {profile}:continue -p "$enhancedPrompt"` via Bash tool

5. **Review (never delegated)**
   - Same as the initial-delegation protocol: run `/code-review` yourself
     against the new commit(s) before considering this closed

6. **Report results**
   - Report: Profile, Session #, Incremental cost, Total cost, Duration, Exit
     code, and your review verdict

## Decision Framework

**Delegate when:**
- Simple refactoring, tests, typos, documentation
- Deterministic, well-defined scope
- No discussion/decisions needed

**Keep in main when:**
- Architecture/design decisions
- Security-critical code
- Complex debugging requiring investigation
- Performance optimization
- Breaking changes/migrations

## Profile Selection Logic

**Task Analysis Keywords** (scan task string with regex):

| Pattern | Variable | Example |
|---------|----------|---------|
| `/(think\|analyze\|reason\|debug\|investigate\|evaluate)/i` | `needsReasoning = true` | "think about caching" |
| `/(architecture\|entire\|all files\|codebase\|analyze all)/i` | `needsLongContext = true` | "analyze all files" |
| `/(typo\|test\|refactor\|update\|fix)/i` | `preferCostOptimized = true` | "fix typo in README" |

**Profile Characteristic Inference** (classify by name pattern):

| Profile Pattern | Cost | Context | Reasoning |
|----------------|------|---------|-----------|
| `/^glm/i` | low | standard | false |
| `/^kimi/i` | medium | long | true |
| `/^claude/i` | high | standard | false |
| others | low | standard | false |

**Selection Algorithm** (apply filters sequentially):

```
profiles = Object.keys(config.profiles)
classified = profiles.map(p => ({name: p, ...inferCharacteristics(p)}))

if (needsReasoning):
  filtered = classified.filter(p => p.reasoning === true).sort(['kimi'])
else if (needsLongContext):
  filtered = classified.filter(p => p.context === 'long').sort(['kimi'])
else:
  filtered = classified.filter(p => p.cost === 'low').sort(['glm', ...])

selected = filtered[0] || profiles.find(p => p === 'glm') || profiles[0]
if (!selected): throw Error("No profiles configured")

log("Selected {selected} (reason: {reasoning|long-context|cost-optimized})")
```

**Override Logic**:
- Parse task for `/--(\w+)/`. If match: `profile = match[1]`, remove from task, skip selection

## Example Delegation Tasks

**Good candidates:**
- "/ccs add unit tests for UserService using Jest"
  → Auto-selects: glm (simple task)
- "/ccs analyze entire architecture in src/"
  → Auto-selects: kimi (long-context)
- "/ccs think about the best database schema design"
  → Auto-selects: kimi (reasoning)
- "/ccs --glm refactor parseConfig to use destructuring"
  → Forces: glm (override)

**Bad candidates (keep in main, don't delegate at all):**
- "implement OAuth" (too complex, needs design first — that's a planning
  skill's job, not implement's or a delegated model's)
- "improve performance" (requires profiling)
- "fix the bug" (needs investigation)

These aren't a weaker profile choice — they fail the `/implement` precondition
(a settled plan with seams) before profile selection is even relevant.

## Execution

**Commands:**
- `/ccs "task"` - Intelligent delegation (auto-select profile)
- `/ccs --{profile} "task"` - Force specific profile
- `/ccs:continue "follow-up"` - Continue last session (auto-detect profile)
- `/ccs:continue --{profile} "follow-up"` - Continue with profile switch

**Agent via Bash:**
- Auto: `ccs {auto-selected} -p "task"`
- Continue: `ccs {detected}:continue -p "follow-up"`

## References

Template: `CLAUDE.md.template` - Copy to user's CLAUDE.md for auto-delegation config
Troubleshooting: `references/troubleshooting.md`
