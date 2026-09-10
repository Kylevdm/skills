# Fleet holds GitHub access; the primary orchestrator passes a reference, delegated agents get nothing

---
status: accepted
---

Fleet ingests a ticket-backed job from a bare `(repository, issue)` reference
and fetches the **input snapshot** itself with the user's ambient `gh`
credentials. The primary orchestrator passes only its judgments — risk class,
acceptance-contract additions, permitted overrides — and never the ticket
content. Delegated agents receive no GitHub credentials, no `gh`, and no Fleet
tools; they see the sealed snapshot as fenced, quoted text.

This is the surprising part worth recording: **Fleet talks to GitHub while the
agents it drives cannot.** A reader who assumes agents inherit their
orchestrator's reach will find that boundary deliberate rather than
unfinished. Fleet also mutates nothing — it opens, closes, comments on, and
pushes to nothing — so the access is read-only in practice.

## Considered Options

- **The primary fetches and passes the snapshot in `SubmitRequest`**: rejected.
  It puts the ticket body, its comment thread, the parent issue, and every
  blocker through the primary's context window, then spends primary *output*
  tokens re-emitting them as a payload — precisely the cost the fleet exists to
  avoid. It also leaves Fleet holding a paraphrase whose fidelity it cannot
  check.
- **Delegated agents fetch their own context with `gh`**: rejected. It hands a
  credential to the least-trusted component in the system, driven by a
  low-cost model acting on issue text written by third parties, and makes the
  brief non-reproducible across a resume.
- **Fleet fetches once, before admission, and seals the result**: chosen. The
  primary spends a reference; Fleet holds a snapshot it acquired and hashed;
  agents hold no capability at all.

The primary still *reads* the issue — it must, to judge the work unsuitable for
delegation and to set the risk class. That read was never the waste. The waste
was transcribing it.

## Consequences

- `SubmitRequest` carries a reference, not content, for ticket-backed jobs.
  Ticket 01's "accepts no GitHub credential" now means literally that: no token
  is ever an argument, and the adapter uses ambient auth.
- Ingestion happens **before** admission, so a failed fetch returns a typed
  Fleet problem and leaves no job record and no dedup-index entry.
- Fleet's usefulness is bounded by the ambient `gh` login. A repository the
  user cannot read is a repository Fleet cannot ingest, and that failure
  surfaces at `submit` rather than mid-job.
- The snapshot is untrusted third-party text entering an agent prompt. The
  guarantee against it is the capability boundary above, not filtering; the
  brief fences it structurally so the boundary is legible.
- Because Fleet reads GitHub's native relations only, a tracker that publishes
  blockers as prose yields tickets that look unblocked. That fix belongs to
  `to-tickets`.
