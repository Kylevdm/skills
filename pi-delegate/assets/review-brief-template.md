READ-ONLY REVIEW. Do not edit any file. Do not run the full test suite more than once.

Repo: <repo> (read <CLAUDE.md / AGENTS.md>, especially its security section). Review <what changed, in
one line> for issue #<N>: `git diff <base> <head> -- <paths>` (commits <shas>; ignore <unrelated parts
of the range>).

Context: <two or three sentences on what the change does and the path it replaces, so the reviewer
knows what "before" looked like.>

Each of these rules must hold, with behaviour identical to <the old path / the spec>:
1. <Safety property, stated as an observable rule, with file:line of where it lives.>
2. <…one line per guard, refusal, fail-closed path or invariant the change sits next to.>

Compare the new code against <the old path / the rules> line by line. Look for any input where the
new code <does more / refuses less / proceeds where the old code stopped> than the old code or these
rules allow.

Final message: a numbered list of concrete findings, each with file:line, the input that triggers it,
what happens, and what should happen. Say "no findings" for each rule you checked and found sound.
No praise, no summary.
