# Fog Ledger Skill

This context defines the language for preserving unresolved work across Wayfinder maps and agent sessions.

## Language

**Fog**:
An in-scope area ahead of an active map that cannot yet be phrased as a precise question. Its source of truth is the map's **Not yet specified** section.
_Avoid_: Idea, backlog item, task

**Patch**:
A single claim that something remains unknown and unowned. A patch may be indexed in the ledger only after grounding confirms that claim is still true.
_Avoid_: Entry, issue, task

**Fog ledger**:
The cross-map index that preserves live patches after their source maps close and records wanted efforts that no map owns. It points to source material rather than duplicating it.
_Avoid_: Backlog, ideas file, map

**Carried patch**:
A grounded patch from a closing map that remains within the map destination's scope but unowned because its trigger has not fired. A patch that blocks the destination prevents closure; a patch beyond the destination is a deferred effort.
_Avoid_: Deferred effort, out-of-scope item

**Deferred effort**:
Wanted work that is outside every current map's destination and owned by none. Random ideas that did not arise from a map enter the ledger in this form.
_Avoid_: Fog, carried patch

**Trigger**:
The observable event that makes a patch or deferred effort ready to become owned work. A trigger may explicitly be absent.
_Avoid_: Deadline, priority

**Sweep**:
A grounding pass over the fog ledger that checks whether its claims, ownership, and triggers remain current.
_Avoid_: Grooming, planning

**Capture**:
The workflow that grounds a newly raised thought and, when it is still wanted but owned by no map, records it as a deferred effort.
_Avoid_: Triage, ticketing

**Drop-off capture**:
An explicitly requested capture that the agent grounds and routes without requiring the human to manage or refine the thought. It asks only when a decision would materially change the human's intent.
_Avoid_: Inbox item, intake interview

**Close-map triage**:
The workflow that classifies every patch on a closing map as answered, rehomed, or carried before the map closes. Only carried patches enter the ledger.
_Avoid_: Sweep, deletion

**Rehomed patch**:
A patch whose concern now has a concrete owner such as another map or ticket.
_Avoid_: Carried patch, answered patch

**Answered patch**:
A patch whose uncertainty has been resolved by current evidence.
_Avoid_: Closed ticket, rehomed patch

**Live ledger**:
A ledger containing only claims that are true today. Resolved or newly owned work leaves the live index; its source map and version history retain provenance.
_Avoid_: Archive, changelog

**Triage mark**:
An ANSWERED, REHOMED, or CARRIED classification left beside the original patch in a closing map, together with the evidence or human rationale supporting it.
_Avoid_: Ledger row, status label

**Partial sweep**:
A sweep that cannot ground every live row or resolve every contradiction. It reports its gaps without advancing the Last swept date.
_Avoid_: Completed sweep

**Last swept**:
The date on which every live ledger row was last grounded and every discovered contradiction resolved. Capture and close-map triage do not advance it unless they also complete a full sweep.
_Avoid_: Last modified, last entry added

**Routing**:
The act of placing a grounded thought with its correct owner: active-map fog in Not yet specified, a sharp question in a ticket, answered work in Decisions so far, carried fog in the ledger, or universally out-of-scope wanted work under Deferred efforts.
_Avoid_: Capture, prioritization
