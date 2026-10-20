# Task: <one line — issue #N title>

You are working in a git worktree of <repo> on branch <branch>, cut from <default branch>.
You cannot commit, push, use `gh`, install packages or reach the network; the orchestrator does
those. Leave your changes uncommitted in the working tree.

## Conventions
Read <AGENTS.md / CLAUDE.md / CONTRIBUTING.md> first and follow it. <Anything about this repo the
file doesn't say: test layout, naming, error-handling idiom.>

## The issue
<Paste the issue text verbatim. The jail can't fetch it.>

## Evidence you can't fetch
<Live payloads, API response shapes, log excerpts, the line numbers you already found. Say where
each came from. Omit the section if there is none.>

## Scope
- Change: <files/modules expected to change>.
- Do not touch: <files outside scope; protected paths are read-only anyway and writes will fail>.
- Out of scope: <related issues to leave alone, with numbers>.

## Safety properties you must preserve
<Name every existing fail-closed path, guard, refusal or validation the change sits next to,
with file:line. For each, say what "preserved" means: e.g. "`supply_guard.check()` still refuses
when the reading is stale (ha_spark/energy/supply_guard.py:88); do not add a fallback that
proceeds". If the fix seems to require relaxing one, stop and explain why in your final message
instead of relaxing it.>

## Done means
- <Behaviour that must now hold.>
- Tests: add or update tests that pin the new behaviour AND the preserved safety properties above.
  Do not delete or weaken existing assertions.
- Gates, all passing: `<lint cmd>`, `<typecheck cmd>`, `<test cmd>`.

## Final message
Summarise: what changed (files), why, the gate results with counts, anything you were unsure of,
and anything you deliberately left alone.
