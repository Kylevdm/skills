---
name: check
description: Pre-clear audit. Before the session's context is cleared, find what would be lost or left inconsistent, report it, and fix what the user approves.
disable-model-invocation: true
---

# Check

The user is about to clear the session. Anything that lives only in this conversation is about to be lost: decisions, facts learned, promises made, files that exist only on this machine. Audit the session for **loose ends**: something lost if the context goes, or left contradicting what was decided. Then report them and fix the ones the user approves.

This is an audit, not a recap. Report only what needs action. A category with nothing in it gets no line.

## 1. Sweep

Work through every category below. Ground each one in a fresh look (a command, a file read, a tracker query) rather than in your recollection of the session. Recollection is exactly what's being audited. The sweep is done when every category has been checked against evidence.

- **Memory.** Durable facts from this session that aren't saved yet: decisions and their reasons, the user's corrections and preferences, ids of things created (issues, PRs, artifacts), the next step. Also existing memories this session made **stale**: a status that moved, a "next" that's done, a pointer to something deleted. Check the memory index line as well as the file.
- **Unpublished work.** Run `git status` in the main checkout and in every worktree (`git worktree list`). Look for untracked or uncommitted files, and for commits that aren't pushed. The sharpest case is a file that something published *points at* (an issue, a spec, a brief, a doc) but that isn't on the default branch. Agents starting from the default branch can't see it.
- **Tracker drift.** Issues, specs and PRs created or edited this session whose text now contradicts a later decision or correction made in conversation. Also check for missing labels, parent/sub-issue links, milestones and cross-references, and for open PRs that are waiting on the user.
- **Hygiene.** Is the checkout on a branch that has already merged? List worktrees and local branches already merged into the default branch. Check that every worktree you'd remove is clean, and say what's in it if it isn't.
- **Running things.** Background jobs, dev servers, watchers and tunnels started this session. Also scratch or `/tmp` files that hold the only copy of something worth keeping.
- **Promises.** Anything you told the user you would do, flag or follow up on that hasn't happened. Also reminders in memory that are due now.
- **Project rules.** Anything the project's instructions (CLAUDE.md, AGENTS.md) require at the end of a piece of work that this session's work skipped, such as changelog fragments, docs or version bumps.

## 2. Report

Give a numbered list, most significant first. Each item says:
- what the loose end is, with its evidence (the path, issue number or command output);
- why it matters if left;
- the action you propose.

Then end with one line on anything that's still open but deliberately left, such as an unmerged branch that isn't this session's.

Ask the user which actions to take. Report first, act after.

## 3. Fix

Do only what the user approved:
- Before deleting or overwriting anything, look at what's there. Force-remove a dirty worktree only after naming its contents and judging them disposable.
- Commit and push only through a branch and a PR, unless the user says otherwise. Edit tracker text in place, and change only the lines that drifted.
- Update memory last, so it records the final state, including anything the fixes created (a PR number, a corrected spec).

Close with what was done, what's left, and whether the session is clear.
