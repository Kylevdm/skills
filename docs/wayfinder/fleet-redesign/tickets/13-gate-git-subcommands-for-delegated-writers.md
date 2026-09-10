---
title: "Gate git subcommands for delegated writers"
labels:
  - wayfinder:grilling
status: open
parent: ../../fleet-redesign.md
assignee: ""
blocked_by:
  - 05-specify-the-pi-work-unit-protocol.md
  - 06-specify-git-isolation-assembly-refresh-and-landing.md
---

## Question

Ticket 06 makes Fleet's correctness depend on no ref outside
`refs/heads/fleet/<jobId>/` ever moving, while ticket 05 gates bash by resolved
argv *head* only and puts `git` on the default accepted-command allowlist. A
writer therefore holds `git` with every subcommand: `branch -f`, `push`, `tag`,
`checkout`, `worktree add`, `-C <any other path>`, and `reset --hard` on a
sibling worktree. Worktree quarantine is explicitly a Git-level separation and
not a security boundary, so nothing currently stops this.

Which git operations may a delegated writer perform, and what enforces it?
Decide whether the command gate inspects subcommands and flags rather than only
the argv head, how `-C` and absolute paths that escape the job's worktree are
handled, whether a violation is a block, a quality failure, or an immediate
return, and what Fleet verifies about its own refs after a writer stage seals —
given that a gate is advisory against an agent that can also invoke git through
a script, a test runner, or a shell it spawns itself.
