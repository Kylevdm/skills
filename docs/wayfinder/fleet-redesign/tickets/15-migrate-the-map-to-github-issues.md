---
title: "Migrate the map to GitHub issues"
labels:
  - wayfinder:task
status: open
parent: ../../fleet-redesign.md
assignee: ""
blocked_by:
  - 10-define-verification-and-rollout-gates.md
  - 11-specify-transcript-retention-and-purge.md
  - 12-specify-the-input-token-estimator.md
  - 13-gate-git-subcommands-for-delegated-writers.md
  - 14-create-the-pi-fleet-public-repo.md
  - 16-specify-check-command-discovery.md
---

## Question

Nothing to decide — [Plan TypeScript packaging and
migration](09-plan-typescript-packaging-and-migration.md) settled that this
effort leaves the local-Markdown tracker at map agreement. Move the whole map
to `Kylevdm/pi-fleet`'s issue tracker: the map as a `wayfinder:map` issue, each
closed ticket as a closed issue carrying its answer verbatim, each open ticket
as an open issue, and blocking rewired as native `sub_issues` and
`dependencies` rather than prose.

Everything migrates. A map whose Decisions-so-far links point back at another
repo's markdown has two homes and works from neither.

**Verify native relations resolve on the migrated closed issues before deleting
`docs/wayfinder/fleet-redesign/`.** That verification is what the `to-tickets`
patch in the map's Not-yet-specified section is waiting on: if GitHub's
relations do not carry, the `to-tickets` fix and this migration both change
shape. Record the finding in the answer either way.

Update the map's `tracker:` front matter and the Notes paragraph naming
local-Markdown as part of the move.
