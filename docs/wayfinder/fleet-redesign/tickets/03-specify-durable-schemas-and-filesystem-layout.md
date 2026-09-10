---
title: "Specify durable schemas and filesystem layout"
labels:
  - wayfinder:prototype
status: closed
parent: ../../fleet-redesign.md
assignee: "claude"
blocked_by:
  - 01-define-fleet-module-interface.md
---

## Question

What versioned per-job records, immutable stage artifacts, leases, audit
records, lock files, and filesystem layout make the Fleet module crash-safe
without a database? Decide schema validation, atomic-write and sealing rules,
redaction, artifact retention, legacy shell-job recognition, path validation,
and how records remain inspectable after clean, archive, cancellation, and a
failed purge request.

## Resolution

Fleet stores every job as files under `$PI_FLEET_HOME` (default `~/.pi/fleet`),
the same root the shell script already uses. New records live in `jobs/`,
`capacity/`, `index/`, and `worktrees/`; legacy shell jobs stay untouched as
`<root>/<repo-basename>/<slug>/`. A directory holding `meta.json` with no
sibling `job.json` is a legacy job: list, inspect, diff, and safe clean only.
The new state machine never writes outside its four subtrees.

```text
~/.pi/fleet/
  store.json                     # {schema, epoch, createdAt}
  config.json                    # limits and targets; ticket 04 owns its content
  index/active.json              # (repoId, issueKey) -> jobId, the dedup index
  capacity/writers-global.json   # capacity leases, fenced by generation
  capacity/writers-<repoId>.json
  worktrees/<jobId>/<role>-<n>/  # disposable; `clean` removes only these
  jobs/<jobId>/                  # jobId is a ULID; the only derived path key
    job.json  job.lock  lease.json  plan.json  git.json  audit.jsonl  tmp/
    input/snapshot.json  input/snapshot.sha256
    stages/NN-<kind>/
      stage.json  call-intent.json  artifact.json  artifact.sha256
      out/diff.patch  out/checks.json  out/review.json  logs/pi.jsonl
```

Job directories are flat under `jobs/`. ULIDs sort by admission time, one
derivation rule covers every path, and a moved checkout cannot orphan a job.
Per-repository grouping is a query over `index/active.json`, not a path.

Eleven versioned record types carry a `schema` field with a major version:
`store`, `job`, `input-snapshot`, `stage-plan`, `stage`, `call-intent`,
`stage-artifact`, `supervisor-lease`, `capacity`, `audit`, and `purge-intent`.
Records are schema-validated on every read. A record whose major version the
running binary does not know makes the store read-only rather than failing
open; only a migration bumps `store.json.epoch`.

`job.json` is the one mutable record per job. It carries a monotonic
`revision`; every mutation takes `job.lock`, compare-and-swaps on that
revision, and returns `conflict` on a stale request. Everything else is
write-once, so a crash can corrupt at most one file, and that file is always
rebuildable from the write-once set.

Every write is `tmp/<name>.<ulid>` -> `fsync(file)` -> `rename()` over the
target -> `fsync(dir)`. `tmp/` sits inside the job directory so a rename never
crosses a filesystem, and an orphaned scratch file is always discardable
because `rename` is the only commit point. `audit.jsonl` is the exception: it
is appended with `O_APPEND`, one entry per mutation.

**Presence is the seal.** `artifact.json` existing is the sealed state of a
stage; `job.json` caching the artifact digest is an index, not the authority.
A crash between the artifact rename and the head update lets recovery verify
the digest, adopt the artifact, and re-index — never repeat the paid call.

**Intent before spend.** `call-intent.json` is fsynced before Pi is spawned and
carries a deterministic `sessionName` of `<jobId>-<stageIndex>-<attempt>`, so a
recovering supervisor reconciles the exact call even when the crash beat the
pid to disk. If the call completed, Fleet seals it; if the process is live, the
new supervisor watches it; if it cannot be identified, the job is returned to
the primary orchestrator. No branch of that walkthrough repeats a paid call.

Every write to `job.json`, `stage.json`, and `capacity/*` carries the writer's
lease generation, and the store rejects a stale or superseded generation.

`clean` removes `worktrees/<jobId>/` and `tmp/` only. `archive` sets `status`
and `archivedAt` in place: paths stay stable for the life of a job id, so every
`ArtifactRef` handed to a caller keeps resolving, and `list` filters archived
jobs by default. `purge` writes `purge-intent.json` with its short-lived token,
recorded branches, and unlanded-branch acknowledgement before deleting
anything; a purge that fails midway leaves that file as a tombstone, excluded
from `list`, never runnable, and retryable with the same token.

Retention keeps the full `logs/pi.jsonl` transcript per stage until purge.
Known credential shapes are scrubbed as the transcript is written and redacted
again before any bounded excerpt leaves the module. Records store
`providerRequestId`, model, and usage — never credentials.

Paths are never built from caller input. A job id must match the ULID pattern,
every resolved path is realpath-checked to be under the root, and the module
derives every other path from the validated id.

Prototype (schemas, layout rules, and a clickable crash walkthrough covering
every write point): branch `prototype/fleet-durable-store`, commit `5db84c9`,
at `fleet/prototypes/durable-store/`.

## Amendment (2026-09-10)

[Plan TypeScript packaging and migration](09-plan-typescript-packaging-and-migration.md)
strikes legacy shell-job support. Fleet does not recognise, list, inspect,
diff, or clean a `meta.json` directory with no sibling `job.json` — it ignores
the pre-cutover store entirely and ships no verb that touches it. The paragraph
above admitting legacy jobs as "list, inspect, diff, and safe clean only" no
longer holds; "the new state machine never writes outside its four subtrees"
now describes reads as well as writes.
