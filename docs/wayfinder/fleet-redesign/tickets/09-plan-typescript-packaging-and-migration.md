---
title: "Plan TypeScript packaging and migration"
labels:
  - wayfinder:grilling
status: open
parent: ../../fleet-redesign.md
assignee: ""
blocked_by:
  - 01-define-fleet-module-interface.md
  - 02-specify-state-machine-and-recovery-protocol.md
  - 03-specify-durable-schemas-and-filesystem-layout.md
  - 05-specify-the-pi-work-unit-protocol.md
  - 06-specify-git-isolation-assembly-refresh-and-landing.md
  - 08-design-the-cli-and-mcp-adapters.md
---

## Question

What packaging, installation, configuration, and cutover sequence moves Fleet
from the shell script to the TypeScript module while retaining a compatibility
shim and read-only legacy-job support? Decide the build and distribution
mechanics, migration of configuration and records, replacement of
`fleet-update`, mechanics, ADRs, and evals, atomic cutover, rollback, and the
point at which old write paths become unavailable.
