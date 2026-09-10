---
title: "Specify the input-token estimator"
labels:
  - wayfinder:grilling
status: open
parent: ../../fleet-redesign.md
assignee: ""
blocked_by:
  - 04-specify-routing-and-evaluation-mechanics.md
  - 05-specify-the-pi-work-unit-protocol.md
---

## Question

How does Fleet estimate a work unit's input tokens before dispatch, so routing
can apply the Qwen3.7 Plus context-band guard and reject an oversized job? The
brief's shape is now fixed — role brief, immutable input snapshot, and the
verbatim sealed artifacts of the depended-on stages. Decide the estimator's
method and its error margin, whether context files and the system prompt are
counted, what the configured margin below the 256K threshold is, and the exact
path taken when a brief exceeds every eligible model's context window.
