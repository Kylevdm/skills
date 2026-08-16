---
name: fog
description: Capture, route, and maintain unresolved future work across sessions and Wayfinder maps in a repository fog ledger. Use when the user says to remember, log, defer, or "fog" a random idea; mentions a future concern with no current owner; asks to sweep or revisit fog; or closes a Wayfinder map whose Not yet specified patches must be triaged.
---

# Fog

Preserve unresolved work without turning it prematurely into a backlog. Treat an active Wayfinder map as the store for its fog and the repository fog ledger as the live cross-map index.

*Fog*, *patch*, *carried*, *deferred effort* and *trigger* are precise terms, defined below where each does its work. Read [references/glossary.md](references/glossary.md) when a distinction is contested — it also records the looser words each term displaces, which is what keeps a ledger from decaying into a backlog.

## Choose the mode

- With no argument, or a request to sweep or revisit fog, run **Sweep**.
- With `close <map>` or a request to close a Wayfinder map, run **Close a map**.
- With a thought, or a request to remember, log, defer, or fog something, run **Capture**.
- When invoked implicitly by a passing speculative remark, make only a lightweight ownership check. Ask a brief, non-blocking capture question while continuing the user's active task. A phrase such as `fog this`, `remember this`, or `log this for later` is explicit authorization.

Interpret this as natural language, not a strict command grammar.

## Locate the ledger and maps

1. Read repository instructions first. Use a configured fog-ledger path when one is named; otherwise use `docs/fog.md`.
2. Read the ledger's own routing table before editing it. Preserve compatible local headings and conventions. If its structure is ambiguous or contradicts the invariants below, show a migration and wait for approval.
3. Read `docs/agents/issue-tracker.md` when present and use its Wayfinding operations. Otherwise infer the tracker from repository evidence; fall back to local Markdown when none is configured. When maps live in the tracker rather than the repository, closure edits both surfaces: the map body through the tracker, the ledger through the file.
4. Note how **Deferred efforts** is grouped. It grows subject subsections as it fills, and entries elsewhere point at them by name. Place a new entry in the subsection it belongs to, or say you are opening one.
5. When the ledger does not exist, initialize it from [assets/fog.md](assets/fog.md). A bare invocation then continues as the first sweep.
6. In a read-only repository, return the exact proposed change and location without claiming it was persisted.

## Keep these invariants

- **Map is store; ledger is index.** Never restate map reasoning in the ledger when a precise pointer suffices.
- **Every live claim is true today.** Ground a patch before it earns a row. One stale row undermines the rows beside it.
- **One owner, one home.** Exclude anything already decided, already ticketed, owned by an active map, or duplicated elsewhere in the ledger.
- **Sharpness routes before ownership.** A precise question is a ticket even when an active map already owns its subject and even when the question is blocked. Only an unsharp area belongs in **Not yet specified**. Work beyond a map's destination is out of scope for that map.
- **Carried is conditional and in scope.** Carry a closing-map patch only when it remains within that destination but its observable trigger did not fire. A blocking patch prevents closure. A patch beyond the destination is a Deferred effort.
- **Deferred is wanted but outside every current destination.** Random ideas with no source map enter here.
- **The ledger is live, not archival.** Remove answered rows and rehome owned work. Source maps and version history retain provenance.
- **Evidence is specific.** Cite tracker items with stable links and repository evidence as `path:line`. Say when no existing touchpoint was found.
- **No invented urgency.** `Trigger: none yet` is valid. A trigger may be human-observable, but someone must be able to determine whether it fired.
- **Last swept is a certification.** Advance it only after grounding every live row and resolving every discovered contradiction. Capture and map closure alone do not advance it.

## Ground a claim

Do the factual work yourself:

1. Read the source map or text that raised the thought.
2. Search the build, documentation, ledger, active maps, and tracker for answers or existing ownership. Use proportional depth: always check the obvious surfaces and deepen when evidence points to prior work.
3. Decide whether the claim is still unknown and unowned.
4. Re-read every target immediately before editing. Preserve concurrent, unrelated changes; stop on a semantic conflict rather than overwriting from an earlier snapshot.

Prefer discovering that a thought is answered or rehomed over manufacturing a ledger row.

## Capture

Explicit capture is a zero-management drop-off. Complete the grounding and routing without interviewing the user unless a decision would materially change their intent.

1. Ground the thought.
2. Route it:
   - Already resolved → report the evidence; add nothing.
   - Already represented by a live ticket or exact map patch → point to that owner; add nothing.
   - Sharp enough to state as a question → identify its owning map when possible and offer a Wayfinder ticket handoff; do not put it in the ledger or **Not yet specified**.
   - One active map owns an unsharp area → add it to that map's **Not yet specified**.
   - Beyond one map but owned by none and still wanted → add it under **Deferred efforts**.
   - Several maps could own it → ask which destination owns it before writing.
3. Write a Deferred effort with three fixed parts: what it is, where it touches the build with evidence when applicable, and its trigger. Use `Trigger: none yet` rather than forcing one. Let grounding set the length — a thought that arrives whole is a line, and one whose shape was argued out in the session earns the paragraph that records the shape and its real cost, since that reasoning is what decays first. Name any other entry the same event releases, so a trigger firing surfaces everything it unblocks.
4. Re-read, apply the smallest edit, and report the actual outcome. Do not advance Last swept.

Resolving a ticket is a common source: the work reveals something past the owning map's destination. Route it as above and attribute it — say which ticket raised it, note it in the map's **Out of scope** with a pointer to the ledger subsection it landed in, and record any map ruling that entry out of scope in the entry itself.

An explicit capture promises preservation and correct routing, not necessarily a ledger row.

## Close a map

Treat fog triage as a closure gate.

1. Load the full map, its **Destination**, every **Not yet specified** patch, the ledger, and relevant current evidence.
2. Ground every patch and recommend one mark:
   - **ANSWERED** — current evidence resolves the uncertainty. State and link the answer.
   - **REHOMED** — a map, ticket, or other scope now owns it. Link the owner.
   - **CARRIED** — it remains within the destination, unowned, and unactivated. Preserve the human's rationale in their own words and add it to the ledger.

   Partial resolution is common and is not a fourth mark. Work that narrowed a patch without closing it leaves it **CARRIED**, with the row rewritten to say what is now settled, what is still open, and what the narrowing did to the trigger. Saying "partly answered by X" and citing X is more useful than either a clean mark or an unchanged row.
3. Reject invalid closure states:
   - A patch that blocks the destination means the map is not ready to close.
   - A patch explicitly beyond the destination belongs under **Out of scope** and, when still wanted but universally unowned, under ledger **Deferred efforts**—never Carried. Point the out-of-scope entry at the ledger subsection holding it, so a reader of the closed map can find where the work went.
4. Present the complete classification frontier with recommendations. Wait for the user to confirm all classifications and supply any missing human rationale before mutating either artifact.
5. Stage closure in this order:
   1. Re-read the targets for concurrent changes.
   2. Leave each original patch in **Not yet specified** and mark it inline with its classification, evidence, and rationale. Head that section with one line stating the triage date, the counts, and where the carried patches now live — someone reading the closed map should learn the fog was handled without opening the ledger.
   3. Update the ledger: add only Carried rows, move genuinely deferred work, change the source-map heading from open to closed when that convention exists, and remove open-map findability wording.
   4. Add one linked **Triaged** entry with the date and ANSWERED, REHOMED, and CARRIED counts. Record zero counts too.
   5. Re-read both artifacts and verify that every patch agrees across them.
   6. Close the tracker map last.
6. If any stage fails, leave the map open and report the exact remaining inconsistency. Do not advance Last swept unless this operation also completed a full sweep.

## Sweep

1. Ground every row under **Carried** and **Deferred efforts** against current code, docs, maps, and tracker state.
2. When tracker operations support it, find closed Wayfinder maps missing complete triage.
3. For each row, check whether it is answered, newly owned, triggered, duplicated, stale, or routed inconsistently.
4. Apply conclusive factual maintenance directly:
   - Remove answered rows.
   - Rehome rows only after the new owner actually exists.
   - Move out-of-scope Carried rows to Deferred efforts when still wanted.
   - Merge rows describing the same thing twice. Keep the sharper wording, fold the loser's reasoning into it rather than dropping it, and amend the source map's **Triaged** entry to record the move — otherwise the ledger disagrees with its own history about what that map carried.
   - Correct citations and stale factual wording.
5. When a trigger fired, explain why the work is now sharp and offer a Wayfinder handoff. Keep the entry live until a map or ticket actually owns it.
6. Ask the user only when continued desire, scope, sharpness, or another genuine decision is unclear.
7. Advance **Last swept** to today's date only after every live row is grounded, all detected missing map triage is resolved, and no contradiction remains. Otherwise report a **partial sweep**, enumerate the gaps, and leave the date unchanged.

## Finish safely

Follow repository-specific validation and delivery instructions. Treat fog changes as documentation unless the repository says otherwise. Do not create commits, open pull requests, push, or publish without authorization.

Report:

- which mode ran;
- what was grounded and where;
- what changed or why nothing changed;
- any offered Wayfinder handoff;
- whether a sweep was complete or partial;
- whether the map remained open or closed.
