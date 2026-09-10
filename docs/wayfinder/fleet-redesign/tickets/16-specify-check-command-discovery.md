---
title: "Specify check-command discovery and the checking stage contract"
labels:
  - wayfinder:grilling
status: open
parent: ../../fleet-redesign.md
assignee: ""
blocked_by: []
---

## Question

Where does the check command come from, and what exactly must the `checking`
stage seal? [Specify the state machine and recovery
protocol](02-specify-state-machine-and-recovery-protocol.md) requires
`checking` to seal passed evidence before a job can reach
`ready-for-acceptance`, and [Specify Git isolation, assembly, refresh, and
landing](06-specify-git-isolation-assembly-refresh-and-landing.md) re-checks
after assembly and after a refresh rebase — but no closed ticket says how the
command is discovered.

Decide: whether it is repository config, planner-declared, detected from the
repository (`package.json` scripts, a Makefile target), or supplied in
`SubmitRequest`; how a repository with no check command is admitted, if at all;
what `out/checks.json` records; whether check failure is a quality failure that
consumes an attempt; and whether the writer's own `commandsRun` count as
checks or only Fleet's independent run does.

## Why it exists

Surfaced by [Define verification and rollout
gates](10-define-verification-and-rollout-gates.md), which requires every gate
to run the repository's real check command and found that nothing specifies it.
The acceptance rates in that ticket's stage-advance criteria are meaningless
until this is settled.
