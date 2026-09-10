---
title: "Specify transcript retention and purge"
labels:
  - wayfinder:grilling
status: open
parent: ../../fleet-redesign.md
assignee: ""
blocked_by:
  - 03-specify-durable-schemas-and-filesystem-layout.md
  - 05-specify-the-pi-work-unit-protocol.md
---

## Question

What retention, size cap, rotation, and purge policy applies to the Pi session
files Fleet keeps as each stage's durable transcript? Decide the per-job and
per-store ceilings, what happens when a job's transcripts exceed them mid-run,
whether an archived job's transcripts are retained at full fidelity or reduced,
how redaction interacts with rotation, and what a failed purge leaves behind.
