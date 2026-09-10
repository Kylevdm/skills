---
title: "Gate git subcommands for delegated writers"
labels:
  - wayfinder:grilling
status: closed
parent: ../../fleet-redesign.md
assignee: "kylevdm"
blocked_by:
  - 05-specify-the-pi-work-unit-protocol.md
  - 06-specify-git-isolation-assembly-refresh-and-landing.md
---

## Question

Ticket 06 makes Fleet's correctness depend on no ref outside
`refs/heads/fleet/<jobId>/` ever moving, while ticket 05 gates bash by resolved
argv *head* only and puts `git` on the default accepted-command allowlist. A
writer therefore holds `git` with every subcommand: `branch -f`, `push`, `tag`,
`checkout`, `worktree add`, `-C <any other path>`, and `reset --hard` on a
sibling worktree. Worktree quarantine is explicitly a Git-level separation and
not a security boundary, so nothing currently stops this.

Which git operations may a delegated writer perform, and what enforces it?
Decide whether the command gate inspects subcommands and flags rather than only
the argv head, how `-C` and absolute paths that escape the job's worktree are
handled, whether a violation is a block, a quality failure, or an immediate
return, and what Fleet verifies about its own refs after a writer stage seals —
given that a gate is advisory against an agent that can also invoke git through
a script, a test runner, or a shell it spawns itself.

## Resolution

The command gate is a **guardrail, and the spec says so** rather than claiming
containment it cannot back. Pi ships no sandbox by design and the writer holds
`bash`, `write`, and `edit`, so it can reach git through a script, a manifest
hook, or a shell it spawns. The gate stops the honest failure — a model that
helpfully runs `git checkout master` or `git push` because that is what
finishing work usually looks like. **Detection protects the invariant**, and it
holds however a ref moved.

**The gate** gains a git-specific rule in the same `tool_call` handler: deny by
default over subcommands, permitting only the writer's real surface (`status`,
`diff`, `log`, `show`, `add`, `commit`, `rm`, `mv`, `restore`, `blame`,
`ls-files`, `rev-parse`, `cat-file`). Deny-by-default absorbs user-configured
aliases without a rule of its own. `stash` is denied along with the obvious ref-
and network-movers, because `refs/stash` sits outside the namespace and
permitting it would manufacture false-positive violations — a writer owning its
worktree exclusively commits instead. Relocating flags (`-C`, `--git-dir`,
`--work-tree`, `--exec-path`, and `GIT_DIR=`/`GIT_WORK_TREE=` argv prefixes) are
refused outright rather than path-resolved, since path containment invites
symlink and `..` bugs in exchange for permitting nothing anyone needs. `write`
and `edit` under any `.git` directory are blocked too — guardrail-grade, since a
heredoc reaches the same files, but it closes the case that actually happens.
The rule is **not overlay-configurable**: the accepted-command list stays
extensible for `cargo` and `go`, while a repo that could overlay `push` back in
has silently opted out of Fleet's correctness. Same policy for `integrating`,
no exception — conflict resolution is `add` plus `commit` on a tree Fleet has
already conflicted.

A denied git command is an **ordinary block** under ticket 05's rule: legible,
non-fatal, counting toward three-blocks-is-a-quality-failure. The reason names
the subcommand, states that Fleet owns ref management, and lists what is
permitted, so a writer does not spend its whole budget rediscovering the rule.

**Verification** is `git for-each-ref` over the *whole repository*, snapshotted
at stage launch and again at seal, for every stage holding `bash` — `writing`
and `integrating` — plus a re-snapshot at recovery, since a crashed supervisor
does not know what happened while it was gone. Narrower scopes were rejected:
the harm is outside the namespace, so a narrow check misses the case it exists
to catch. Not run around Fleet's own git operations, where it would test
nothing. Baseline is every ref unchanged except the stage's own branch, which
may move freely including non-fast-forward; the sealed sha comes from the seal,
never inferred from the ref.

**A violation returns the job immediately**, naming the ref and both shas. Not a
quality failure — the work was not bad, Fleet's model of the repository is
untrustworthy, and retrying inside it compounds the damage. Not ticket 10's
`abort` — that demotes the autonomy stage for every job over what may be the
user's own commit. **Fleet never restores the moved ref**: repairing the
invariant by writing outside the namespace still breaks it, and ticket 06 made
that rule absolute. The false positive from a concurrent user commit is an
accepted cost, mitigated only by snapshotting at stage launch rather than job
start; reflog forensics is rejected because parsing a prunable, format-unstable
local log to decide whether to trust the repository fails permissively, which
defeats the check entirely.

**Records** split by purpose: individual blocks and the verification outcome go
in the stage attempt record (ticket 03), since the return reason cites them; the
aggregate — which models trip the gate, how often, on which subcommands — goes to
ticket 04's append-only evidence log, where only `fleet-update` acts on it.

Spec: [assets/13-git-gate/spec.md](../assets/13-git-gate/spec.md)
