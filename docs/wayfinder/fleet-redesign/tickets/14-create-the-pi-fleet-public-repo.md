---
title: "Create the pi-fleet public repository"
labels:
  - wayfinder:task
status: open
parent: ../../fleet-redesign.md
assignee: ""
blocked_by: []
---

## Question

Nothing to decide — [Plan TypeScript packaging and
migration](09-plan-typescript-packaging-and-migration.md) settled the shape.
Create `Kylevdm/pi-fleet`: public, MIT, fresh history, containing only a README
that states the repo is design-stage and links `Kylevdm/skills` for provenance.
No module content moves yet; that is step 2 of the cutover sequence.

The repo is needed **now**, ahead of the content, because
[Migrate the map to GitHub issues](15-migrate-the-map-to-github-issues.md)
moves this map's tickets onto its issue tracker at map agreement.

AFK: `gh` is authed as `Kylevdm` over SSH on this machine. Record in the answer
the repo URL and the clone path chosen for `npm link`, since the cutover
sequence and `fleet mcp install` both depend on that path.
