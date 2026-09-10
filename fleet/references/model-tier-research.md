# Model tier research

Last checked: 2026-09-10

This note records Fleet's initial calibration pool and current provider costs.
The initial economy, standard, and premium placements are hypotheses. Accepted
Fleet jobs may move the operational tier boundaries once the evidence threshold
is met and the user invokes `fleet-update`.

## Provider budgets

OpenCode Go documents base limits of $12 per five hours, $30 per week, and $60
per month. It gives each model an effective exclusive-use allowance. The public
documentation says effective allowance varies by model, but it does not publish
the cross-model calculation as an equation.
([OpenCode Go usage limits](https://dev.opencode.ai/docs/go/),
[official source](https://github.com/anomalyco/opencode/blob/dev/packages/web/src/content/docs/go.mdx))

Observed account behavior shows that Go tracks one normalized fraction, not an
independent dollar pot for each model. Spending $30 with a model whose
exclusive-use allowance is $60 consumes half of the shared allowance. A model
with a $15 exclusive-use allowance would then have $7.50 of equivalent usage
left.

The working calculation for each limit window is:

```text
fraction consumed = sum(model-dollar spend / that model's exclusive-use allowance)
equivalent amount left for model B = model B allowance * (1 - fraction consumed)
```

Treat the equation as observed account behavior. The public documentation
supports the base limits and model-dependent allowances, but does not state the
equation. Routing between Go models changes how quickly the same normalized
allowance burns.

Direct DeepSeek API calls use pay-as-you-go credits in a separate wallet. They
do not consume the Go allowance. Fleet must report Go normalized burn and
DeepSeek wallet cost separately.

## Evaluation pool

The table is ordered by output-token price, cheapest first. Prices are US
dollars per one million tokens. All Go models in the pool have a $60
exclusive-use monthly equivalent within Go's normalized shared allowance.
([OpenCode Go pricing and endpoints](https://dev.opencode.ai/docs/go/),
[OpenCode Go source](https://github.com/anomalyco/opencode/blob/dev/packages/web/src/content/docs/go.mdx),
[DeepSeek pricing](https://api-docs.deepseek.com/quick_start/pricing/))

| Order | Model and rate band | Pi model | Input | Output | Cached read | Cached write | Budget | API |
| ---: | --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| 1 | MiMo V2.5 | `opencode-go/mimo-v2.5` | $0.14 | $0.28 | $0.0028 | Not listed | Go $60 equivalent | Chat Completions |
| 2 | Hy3 | `opencode-go/hy3` | $0.14 | $0.58 | $0.035 | Not listed | Go $60 equivalent | Chat Completions |
| 3 | DeepSeek V4 Flash, off peak | `deepseek/deepseek-v4-flash` | $0.22 | $0.66 | $0.007 | Not listed | Direct API wallet | Chat Completions |
| 4 | LongCat-2.0 | `opencode-go/longcat-2.0` | $0.30 | $1.20 | $0.006 | Not listed | Go $60 equivalent | Chat Completions |
| 5 | MiniMax M3 | `opencode-go/minimax-m3` | $0.30 | $1.20 | $0.06 | Not listed | Go $60 equivalent | Messages |
| 6 | DeepSeek V4 Flash, peak | `deepseek/deepseek-v4-flash` | $0.44 | $1.32 | $0.014 | Not listed | Direct API wallet | Chat Completions |
| 7 | Qwen3.7 Plus, at most 256K input tokens | `opencode-go/qwen3.7-plus` | $0.40 | $1.60 | $0.04 | $0.50 | Go $60 equivalent | Messages |
| 8 | DeepSeek V4 Pro, off peak | `deepseek/deepseek-v4-pro` | $0.66 | $1.98 | $0.022 | Not listed | Direct API wallet | Chat Completions |
| 9 | DeepSeek V4 Pro, peak | `deepseek/deepseek-v4-pro` | $1.32 | $3.96 | $0.044 | Not listed | Direct API wallet | Chat Completions |
| 10 | Kimi K2.7 Code | `opencode-go/kimi-k2.7-code` | $0.95 | $4.00 | $0.19 | Not listed | Go $60 equivalent | Chat Completions |
| 11 | Kimi K2.6 | `opencode-go/kimi-k2.6` | $0.95 | $4.00 | $0.16 | Not listed | Go $60 equivalent | Chat Completions |
| 12 | GLM-5.2 | `opencode-go/glm-5.2` | $1.40 | $4.40 | $0.26 | Not listed | Go $60 equivalent | Chat Completions |

DeepSeek uses one model ID for both time bands. Peak hours are 01:00 to 04:00
and 06:00 to 10:00 UTC, Monday through Friday. All other hours, including
weekends, use the off-peak rate. Fleet must record the rate band used for each
attempt.
([DeepSeek pricing](https://api-docs.deepseek.com/quick_start/pricing/))

Qwen3.7 Plus has a higher price above 256K input tokens. Fleet's ticket
decomposition is expected to keep every Qwen work unit below that threshold,
so the higher rate is outside the evaluation pool. Fleet should reject or
reroute a Qwen brief expected to cross 256K rather than silently enter the
higher band.

## Availability and compatibility

OpenCode's current model and endpoint tables document every Go ID in the pool.
([OpenCode Go model list and endpoints](https://dev.opencode.ai/docs/go/))

The installed Pi 0.85.1 catalog exposed every Go ID in the pool on 2026-09-09.
It exposed the direct DeepSeek models as
`deepseek/deepseek-v4-flash` and `deepseek/deepseek-v4-pro`. Both have a
one-million-token context window, a 384K maximum output, and reasoning support.
Pi's provider documentation confirms that `deepseek` and `opencode-go` are
separate built-in API-key providers.
([Pi model catalog](https://pi.dev/models?provider=opencode-go),
[Pi provider documentation](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/providers.md))

A catalog entry proves that Pi can resolve an ID and has API metadata for it.
It does not prove that a coding-agent request will complete. Before adding any
candidate to Fleet's routing table, run a small completion through Pi and then
one representative tool call. The pool spans
Messages and Chat Completions. OpenCode lists current Pi builds as validated
clients, but that validation does not cover every model and task.
([OpenCode Go client and endpoint documentation](https://dev.opencode.ai/docs/go/))

## Excluded models

Muse Spark 1.2 Contributor and Muse Spark 1.3 Contributor are excluded because
OpenCode says Meta may use their prompts and completions to train future
models. OpenCode also marks them as not zero-data-retention. This conflicts
with Fleet's no-training rule.
([OpenCode Go privacy table](https://dev.opencode.ai/docs/go/),
[Meta Contributor pricing and terms](https://dev.meta.ai/docs/pricing-rate-limits#contributor-tier))

MiniMax M2.7, MiniMax M2.5, GLM-5.1, and Qwen3.6 Plus are excluded from this
evaluation. Qwen3.7 Plus above 256K is not a
separate candidate because Fleet will keep Qwen work units below 256K. Earlier
candidates such as Qwen3.8 Flash and GPT-5.6 Luna are also outside the approved
pool. Direct DeepSeek V4 Flash and V4 Pro remain in scope, while their OpenCode
Go routes do not.

## Initial calibration tiers

The initial tier pools are:

| Operational tier | Initial output-price region | Candidates |
| --- | ---: | --- |
| Economy | Below $1 on Go | MiMo V2.5, Hy3 |
| Standard | $1–$3 on Go | LongCat-2.0, MiniMax M3, Qwen3.7 Plus |
| Premium | Proven recovery and initial $3+ Go candidates | Kimi K2.7 Code, Kimi K2.6, GLM-5.2, direct DeepSeek V4 Flash and V4 Pro |

Output price gives the evaluation a first ordering because agent runs generate
reasoning and code. Cached-read price can dominate a long Pi session, so Fleet
must calculate the actual cost of each attempt. Direct DeepSeek cost cannot be
compared directly with Go normalized burn because it draws from a separate
wallet.

GLM-5.2 is the initial default premium recovery model because it draws from the
Go allowance. Direct DeepSeek is premium recovery or overflow from a separate
wallet. Comparable work rotates among candidates during calibration rather
than treating the default as established evidence.

After evaluation, operational roles take precedence over permanent price
labels. If the initial economy pool rarely succeeds, the $1–$3 Go candidates
may become economy and the $3+ Go candidates may become standard, while
GLM-5.2 and direct DeepSeek remain allowlisted premium recovery choices. Any
promotion or demotion is made through `fleet-update`, not automatically.

## What Fleet must measure

Provider descriptions and model names are not evidence of agentic coding
success in Pi. OpenCode says it tests model/provider combinations for coding
agents, but it does not publish per-model results for Fleet's prompts, tools,
worktrees, or acceptance contracts.
([OpenCode Go background and goals](https://dev.opencode.ai/docs/go/))

Record every attempt, including rejected work and jobs returned to the primary
orchestrator. Capture the work-unit role, risk class, model, context or time
price band, input, cached, and output tokens, checks, reviewer verdict,
escalation, primary-orchestrator repair, and final acceptance. Record normalized
Go allowance consumed for Go attempts and wallet cost for direct DeepSeek
attempts as separate measures.

Rotate comparable work between candidates in the same tier, role, and risk
class. Require at least ten comparable attempts per cohort before changing a
default. Twenty attempts is a better first decision point. There is no calendar
deadline: continue rotating until the evidence is sufficient and the user
invokes `fleet-update`. When evaluating, use a rolling four-week window and:

- Acceptance without escalation.
- Acceptance without primary-orchestrator code changes.
- Median normalized Go allowance consumed per accepted work unit, or median
  direct DeepSeek wallet cost.
- Median elapsed time per accepted work unit.
- Scope violations, wrong-target edits, false success reports, and missed
  acceptance-contract checks.

The first evaluation should identify the cheapest model that can handle
scouting and mechanical work, the cheapest model that can handle normal
implementation, and the model that best recovers a failed normal attempt.
Capability tiers should follow those results rather than model prices or names.
