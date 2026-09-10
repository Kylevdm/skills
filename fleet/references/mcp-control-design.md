# MCP control for Fleet

Research date: 2026-09-10.

## Recommendation

Expose Fleet to the primary Codex or Claude orchestrator through a small local
MCP server. Run that server as a separate process owned by the MCP host. Do not
install a Fleet MCP client inside delegated Pi agents.

Keep one Fleet application layer behind both MCP and a human-facing CLI. That
layer owns job records, leases, state transitions, model rotation, worktrees,
acceptance, and cleanup. The MCP server should translate typed tool calls to
that layer. It should not wrap shell output from `fleet.sh` as if prose were an
API.

Fleet can control an individual Pi process through Pi's JSONL RPC mode. If
Fleet is implemented in Node, Pi's SDK is also an option. This gives two clear
directions:

```text
Codex or Claude -> Fleet MCP server -> Fleet application layer
                                      -> Pi RPC or SDK -> delegated Pi agent
```

MCP belongs on the first arrow. Pi RPC or the SDK belongs on the second.

## Facts that drive the choice

The current Fleet script already owns more than a Pi session. It creates a
worktree and branch, records metadata outside the repository, derives status
from process and exit-code files, collects logs and diffs, resumes a named Pi
session, and controls landing and cleanup. See `fleet/scripts/fleet.sh:1-31`,
`:193-303`, and `:306-552`. The redesign adds durable stage artifacts and job
records, explicit acceptance, archive and purge semantics, and assembly work.
See `fleet/CONTEXT.md:111-174`. Those are Fleet operations, not Pi session
operations.

Pi 0.85.1 does not include an MCP client or server. Its installed documentation
says that MCP support must come from an extension or package. Extensions run
with full system access. See:

- `/home/kyle/.nvm/versions/node/v22.23.1/lib/node_modules/@earendil-works/pi-coding-agent/README.md:386-412`
- `/home/kyle/.nvm/versions/node/v22.23.1/lib/node_modules/@earendil-works/pi-coding-agent/README.md:495-501`
- `/home/kyle/.nvm/versions/node/v22.23.1/lib/node_modules/@earendil-works/pi-coding-agent/docs/usage.md:305-310`

Pi does provide interfaces for process integration. RPC mode uses correlated
JSON commands and responses over stdin and stdout and streams events as JSONL.
It supports prompts, steering, follow-ups, aborts, queue control, state queries,
and message retrieval. Pi recommends its SDK for a Node application and RPC for
process isolation or a language-neutral client. See the installed
`docs/rpc.md:1-37`, `:43-211`, and `docs/sdk.md:1150-1169`.

MCP tools have JSON schemas and model-driven invocation. The MCP specification
requires servers to validate inputs, enforce access control, sanitize outputs,
rate-limit calls, and expects clients to apply timeouts and confirmation for
sensitive operations. The protocol does not supply Fleet's lifecycle policy.
See the [MCP tools specification](https://modelcontextprotocol.io/specification/draft/server/tools).
For a local stdio server, the MCP host starts the process and owns its lifetime;
stdio credentials come from the environment rather than the HTTP authorization
flow. See the [MCP TypeScript SDK server guide](https://ts.sdk.modelcontextprotocol.io/v2/get-started/first-server)
and [MCP authorization specification](https://modelcontextprotocol.io/specification/draft/basic/authorization).

The `agent-pi` package is useful precedent, not a dependency. It adds an
optional Pi-side bridge that exposes a separate Commander service's tools as Pi
tools. It does not make Pi itself the durable external control API. See the
project's [extension list and Commander configuration](https://github.com/ruizrica/agent-pi/blob/main/README.md#extensions).
Other small projects expose Pi itself through MCP, which confirms that the host
adapter works, but their session registries do not cover Fleet's Git, evidence,
acceptance, or retention rules. For examples, see
[`pi-subagent`](https://github.com/guyiicn/pi-subagent) and
[`pi-cli-mcp`](https://github.com/minmax/pi-cli-mcp).

## Proposed MCP interface

Use compact structured results. Large diffs and raw logs should be fetched only
when requested.

| Tool | Purpose | Mutation |
|---|---|---|
| `fleet_submit` | Validate and create a job, then return its ID and initial state | Yes |
| `fleet_list` | List jobs with filters for repository, state, and active or archived records | No |
| `fleet_get` | Return state, current stage, attempts, model choices, branch refs, and blockers | No |
| `fleet_report` | Return the compact acceptance report and artifact references | No |
| `fleet_diff` | Return a bounded diff, summary, or an artifact reference | No |
| `fleet_checks` | Return commands, exit status, duration, and bounded output for each check | No |
| `fleet_continue` | Resume a returned or rejected job with explicit new instructions | Yes |
| `fleet_accept` | Record the primary orchestrator's acceptance without changing the primary branch | Yes |
| `fleet_land` | Land an accepted commit or assembly branch after safety checks | Yes |
| `fleet_clean` | Remove disposable worktrees and build state but retain the job record | Yes |
| `fleet_archive` | Mark a completed record inactive | Yes |
| `fleet_purge` | Permanently delete one archived record after a preview-token confirmation | Destructive |

Do not expose a generic `fleet_exec` tool or arbitrary command string. Fleet's
state machine should validate every transition. Long-running calls such as
`fleet_submit` should return after durable admission, not remain open for the
whole job. The orchestrator can poll `fleet_get`, or the MCP server can adopt
MCP task support later if both Codex and Claude handle it reliably.

## Security boundary

Use stdio by default. A local MCP host launches one Fleet server for the user,
so Fleet does not need a listening port or an HTTP bearer token. The Fleet
process may read Pi's provider credentials from Pi's normal credential store,
but tool arguments, results, job records, prompts, and logs must never contain
those credentials.

The server should enforce these rules independently of the primary model:

- Resolve repository paths to real paths and require an explicit allowlist.
- Validate job IDs and artifact names. Never accept caller-supplied state-file
  paths, shell fragments, branch commands, or provider credentials.
- Keep report, diff, and check output bounded. Redact known credential shapes
  before returning content to the orchestrator.
- Require a sealed `ready-for-acceptance` artifact before `fleet_accept`.
- Require recorded acceptance, the expected base revision, and a safe primary
  worktree before `fleet_land`.
- Make `fleet_clean` retain the record as the glossary requires. Permit it only
  when no active process or unsealed work can be lost.
- Make `fleet_purge` a two-call operation. The first call returns the exact
  record and artifact inventory plus a short-lived token. The second call must
  repeat the job ID and token. Limit purge to archived terminal jobs.
- Keep an audit entry for every mutating tool call, including rejected calls.

MCP does not turn the worktree into a security sandbox. Current Fleet and Pi
documentation agree that Pi runs with the launching user's filesystem access.
The worktree isolates Git changes, not credentials, the network, or other
files. An MCP adapter must not describe this as sandboxing.

## Do delegated Pi agents need MCP?

No, not for Fleet orchestration. A writer or reviewer should receive a bounded
assignment, repository access, approved commands, and a structured output
contract. Giving it Fleet control would let an ephemeral agent submit or land
jobs, inspect unrelated records, recurse into more agents, and reach retention
operations. It would also duplicate the primary orchestrator's authority.

A Pi-side MCP client may be added later for a specific work unit that needs an
external service. That should be an opt-in tool allowlist for that role and job,
with separately scoped credentials. It should not include Fleet control tools.

## Decision

Build the Fleet MCP server as a northbound adapter for primary orchestrators.
Keep the CLI as a supported adapter over the same application layer. Use Pi RPC
or the SDK internally. Do not put Fleet MCP inside Pi, and do not install an
MCP extension into every delegated session.
