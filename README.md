# skills

Agent skills, one directory each. Everything a skill owns lives inside its own
directory — glossary, decision records, templates — so a skill can be copied out
whole.

## fog

Capture, route and maintain unresolved future work across sessions and Wayfinder
maps in a repository fog ledger. See [fog/SKILL.md](fog/SKILL.md); the reasoning
behind a standalone ledger is in
[fog/docs/adr/0001-standalone-cross-map-fog-ledger.md](fog/docs/adr/0001-standalone-cross-map-fog-ledger.md).

## ccs-fleet

Deploy coding agents through the [CCS](https://github.com/kaitranntt/ccs) CLI,
each isolated in its own git worktree and branch, so an agent that writes files
unattended cannot touch the tree you are working in. Covers profile routing,
writing briefs an agent can follow cold, and reviewing before landing. See
[ccs-fleet/SKILL.md](ccs-fleet/SKILL.md); the verified CLI mechanics and failure
modes are in [ccs-fleet/references/mechanics.md](ccs-fleet/references/mechanics.md).

## ccs-fleet-update

Maintenance skill for ccs-fleet itself: add/remove/rename a profile, point a
profile at a different model, or rebalance the routing table when pricing or
quota changes. Keeps the script, SKILL.md, mechanics.md, evals, and both
install locations in sync instead of hand-editing ccs-fleet's files
directly. See [ccs-fleet-update/SKILL.md](ccs-fleet-update/SKILL.md).

## ccs-delegation

Single-shot delegation to one CCS profile (`ccs {profile} -p "task"`), no
worktree isolation — for one task at a time rather than fanning several out.
Every delegated task is framed as an `/implement` run per the mattpocock
`implement` skill (TDD at seams, typecheck, full suite, commit); code-review
is never delegated, the orchestrating session always runs it against the
result before calling the task done. See
[ccs-delegation/SKILL.md](ccs-delegation/SKILL.md). Reach for `ccs-fleet`
instead when tasks are independent and worth parallelizing.

## Installing

Symlink a skill into your Claude Code skills directory, so edits here are live
without a copy step:

```sh
git clone git@github.com:Kylevdm/skills.git ~/skills
ln -s ~/skills/fog ~/.claude/skills/fog
ln -s ~/skills/ccs-fleet ~/.claude/skills/ccs-fleet
ln -s ~/skills/ccs-fleet-update ~/.claude/skills/ccs-fleet-update
ln -s ~/skills/ccs-delegation ~/.claude/skills/ccs-delegation
```

(On this machine the installed skills are plain copies, not symlinks —
`ccs-fleet-update` accounts for that and syncs with `rsync` instead.)
