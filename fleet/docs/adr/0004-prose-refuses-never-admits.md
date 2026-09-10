# Prose blockers can refuse admission, but never grant it

---
status: accepted
---

Fleet gates admission on a tracker's **native** relations only, never on
`Blocked by #N` prose — [ADR 0003](0003-fleet-owns-github-access.md) settled
that, because a false negative is silent and starts a writer on unfinished
ground. Fleet nonetheless **reads** that prose, and refuses to admit a ticket
whose structured `## Blocked by` section names an issue that no native relation
backs. The refusal is `unverifiable-blocker`.

This is the surprising part worth recording: **Fleet parses the prose it
declared it would not parse.** A reader holding ADR 0003 will find prose-reading
code and take it for a regression. It is not, because of one asymmetry — prose
can only ever *refuse* admission, never satisfy a gate. Native relations remain
the sole positive source for what blocks work. Reading prose adds a way to say
no; it adds no way to say yes, so it cannot reintroduce the silent false
negative ADR 0003 closed. It strengthens that invariant rather than trading
against it.

## Considered Options

- **Fix the publisher — make `to-tickets` write native relations**: rejected,
  and this ADR is the reversal of ADR 0003's closing bullet, which had assigned
  the fix there. `to-tickets` ships from a third-party plugin installed
  read-only, so an edit does not survive an update; its guidance is soft by
  construction (*"where it has one"*) while its template emits prose sections
  unconditionally; and Fleet does not choose its publisher — the primary
  orchestrator points Fleet at a ticket, whatever produced it. Enforcement at
  the publisher can only be requested. At the consumer it can be observed.
- **Ignore prose entirely, as ADR 0003 literally says**: rejected. It is the
  status quo, and it is the one silent failure left in ingestion: a
  prose-only ticket looks unblocked and is admitted. Fleet already holds the
  body in the snapshot, so the check costs nothing.
- **Scan the whole body for issue references**: rejected. It misfires on
  ordinary text — "this supersedes #12" is not a blocker claim — and refusing
  real work over a passing mention is worse than the gap it closes.
- **Read only the structured `## Blocked by` heading**: chosen. Narrow enough
  to have no plausible false positive, since the section exists to list
  blockers and says "None" when there are none.

## Consequences

- ADR 0003's final bullet is superseded: the prose-tracker fix is Fleet's, not
  `to-tickets`'s. No change to any publisher is required or expected.
- `unverifiable-blocker` is distinct from the ordinary open-blocker refusal
  because the human's next move differs — an open blocker means *wait*, an
  unverifiable one means *fix the tracker*. The refusal message carries its own
  remedy; there is no separate tracker-conformance document to consult, and so
  none to drift.
- Fleet's demands on a tracker are stated as **tracker conformance**, in
  capabilities rather than GitHub nouns: a machine-readable parent relation and
  a machine-readable blocker relation. GitHub's `sub_issues` and
  `dependencies/blocked_by` are the only binding implemented today, not a
  permanent assumption.
- Blockers are mandatory; the parent relation is only recommended. They fail
  differently — an unbacked blocker is a correctness failure, an unbacked
  parent merely costs the writer scope context. A missing parent is admitted
  and recorded twice: a flag on `job.json` for `list` and `status`, and a line
  in the brief telling the writer its context is incomplete, since the writer
  is the party harmed by the gap.
- A tracker whose publisher uses different prose gets no protection from this
  check. That is accepted: the check is a backstop against a known template,
  not a parser, and widening it is what the rejected whole-body scan was.
