# Fog ledger

Fog is the dim view ahead of an active map: in-scope areas you can tell are coming but cannot yet phrase sharply enough to ticket. The map's **Not yet specified** section is the store for active-map fog. This ledger is the live index across maps and sessions.

Last swept: Never.

## Where to put things

| It is… | It goes… |
| --- | --- |
| Unsharp and in scope for an active map | That map's **Not yet specified** |
| Sharp enough to state as a question | A ticket on its map, even if blocked |
| Already decided | The map's **Decisions so far**, linking the resolution |
| Past one map's destination but wanted and owned by no current map | **Deferred efforts** |
| Conditional, within a closing map's destination, unowned, and not triggered | Mark **CARRIED** on the map and index it under **Carried** |
| A random wanted idea with no source map or owner | **Deferred efforts** |

Closing a map requires marking every patch in **Not yet specified**:

- **ANSWERED** — current evidence resolved it; state and link the answer.
- **REHOMED** — another map, ticket, or scope owns it; link the owner.
- **CARRIED** — still within the destination, still unowned, and its trigger did not fire; preserve the human's rationale and index it below.

A patch that blocks the destination prevents closure. Work explicitly beyond the destination is never Carried.

Every live row states what it is, cites where it touches the build when applicable, and names the observable event that makes it ready for owned work. `Trigger: none yet` is valid.

## Carried

Live conditional fog from closed maps, grouped by the map that raised it.

<!--
### From [Map title](map link) (closed)

| Patch | Trigger |
| --- | --- |
| What remains unknown, with evidence such as `path:line` or a linked issue | Observable trigger, or none yet |
-->

## Triaged

Closed maps whose **Not yet specified** patches are all marked. Record maps with zero patches too.

<!-- - [Map title](map link) — triaged YYYY-MM-DD: 0 ANSWERED, 0 REHOMED, 0 CARRIED. -->

## Deferred efforts

Wanted work outside every current map's destination and owned by nobody. An idea that never came from a map belongs here too.

<!--
- **What it is.** Where it already touches the build, with evidence, when applicable.
  Trigger: none yet.
-->
