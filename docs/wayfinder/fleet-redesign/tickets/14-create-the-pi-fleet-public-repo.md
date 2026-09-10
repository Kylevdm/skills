---
title: "Create the pi-fleet public repository"
labels:
  - wayfinder:task
status: closed
parent: ../../fleet-redesign.md
assignee: "claude"
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

## Answer (2026-09-10)

Done. `Kylevdm/pi-fleet` exists: **https://github.com/Kylevdm/pi-fleet** —
public, MIT, issues enabled, default branch `main`, fresh history with a single
commit (`2a0bea6`) containing only `README.md` and `LICENSE`. No module content
moved; that stays step 2 of
[Plan TypeScript packaging and migration](09-plan-typescript-packaging-and-migration.md)'s
cutover sequence.

### Facts later tickets depend on

- **Clone path for `npm link`: `~/pi-fleet`.** Chosen to match how `~/skills`
  and `~/ceng` already sit directly under home. The repo was built at that path
  and pushed from it, so the working copy *is* the `npm link` source — there is
  no separate create-then-clone step to sequence, and step 3 of the cutover
  reduces to `npm link` plus `fleet mcp install` against a checkout that is
  already in place.
- **`fleet mcp install` therefore resolves `bin/fleet` at
  `~/pi-fleet/bin/fleet`** once step 2 lands the module content. Ticket 09's
  no-build decision means that path is the shipped code, not a build output.
- **Issues are enabled**, which is the precondition
  [Migrate the map to GitHub issues](15-migrate-the-map-to-github-issues.md)
  was waiting on. That ticket's own first act — testing whether native
  `sub_issues` and `dependencies/blocked_by` relations are writable here — is
  now unblocked on this side.
- **MIT copyright holder is recorded as `kylevdm`**, the GitHub handle rather
  than a legal name. Cosmetic and changeable by a one-line PR; noted only
  because it is public.

### Not done here, deliberately

No repository settings beyond creation defaults were touched — no branch
protection, no labels, no issue templates. Whatever the map needs on the issue
tracker is
[Migrate the map to GitHub issues](15-migrate-the-map-to-github-issues.md)'s to
decide, and guessing at it now would pre-empt that ticket.
