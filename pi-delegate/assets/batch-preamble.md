You are implementing ONE ticket of spec #<SPEC-N> in the <repo> repo. Your working directory is a git
worktree on the ticket's branch, based on the integration branch, which already holds every ticket
this one depends on. You cannot commit; leave changes in the working tree. Do not touch anything
outside this worktree.

## Repo conventions
Read <CLAUDE.md / AGENTS.md> (security rules, conventions), <CONTEXT.md / glossary> (use its
vocabulary), and the module docstrings of every module you change. <Language, typing, lint rules.>
Match surrounding code's naming, comment density and idiom. Simplest solution; no abstractions the
ticket doesn't ask for; don't touch unrelated code or other tickets' scope.

## Method: test-driven
Red-green-refactor, one behaviour at a time: write a failing test that pins external behaviour
(<public entry points>, never private helpers), make it pass with the minimum code, refactor,
repeat. Tests live <where>.

## Gates (all must be green before you finish)
    <lint cmd>
    <typecheck cmd>
    <test cmd>
<Any golden/baseline test that must stay green UNCHANGED.> Do not edit existing tests' expected
values to make them pass; if an existing test genuinely contradicts the ticket, stop and explain in
your final message instead.

## Never change (safety; the reviewer will probe each)
<Every guard, fail-closed path and invariant the spec's tickets sit next to, with file:line and what
"preserved" means. Write this once for the whole batch; ticket notes add ticket-specific ones.>
- Do not bump versions or edit changelogs unless your ticket says so.

## Final message
List: files changed, tests added (names), any ticket criterion not met and why, any place you were
unsure.

## The spec (#<SPEC-N>), for context
{SPEC}

## YOUR TICKET
{TICKET}
