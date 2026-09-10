---
title: "Design the CLI and MCP adapters"
labels:
  - wayfinder:prototype
status: open
parent: ../../fleet-redesign.md
assignee: ""
blocked_by:
  - 01-define-fleet-module-interface.md
  - 02-specify-state-machine-and-recovery-protocol.md
  - 03-specify-durable-schemas-and-filesystem-layout.md
---

## Question

How do the compatibility JSON CLI and local stdio MCP server expose the Fleet
module without duplicating its policy? Decide typed requests and bounded,
credential-redacted responses; polling and durable admission; diff and check
evidence bounds; repository-root allowlisting; mutation auditing; confirmation
for destructive operations; explicit reversible Codex and Claude registration;
and compatibility behavior for legacy shell jobs.
