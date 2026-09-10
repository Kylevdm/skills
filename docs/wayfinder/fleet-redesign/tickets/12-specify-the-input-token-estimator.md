---
title: "Specify the input-token estimator"
labels:
  - wayfinder:grilling
status: closed
parent: ../../fleet-redesign.md
assignee: "kylevdm"
blocked_by:
  - 04-specify-routing-and-evaluation-mechanics.md
  - 05-specify-the-pi-work-unit-protocol.md
---

## Question

How does Fleet estimate a work unit's input tokens before dispatch, so routing
can apply the Qwen3.7 Plus context-band guard and reject an oversized job? The
brief's shape is now fixed — role brief, immutable input snapshot, and the
verbatim sealed artifacts of the depended-on stages. Decide the estimator's
method and its error margin, whether context files and the system prompt are
counted, what the configured margin below the 256K threshold is, and the exact
path taken when a brief exceeds every eligible model's context window.

## Resolution

The **estimated input** is a deliberately crude pre-dispatch tripwire over the
bytes Fleet itself assembles, divided by a fixed constant, compared against a
generous ratio of each model's limit. It is not a model of the run's peak
context, and it is not evidence about which models to use.

### What the estimator is for

Two consumers, both of which must decide *before* a first message exists, which
is why real usage cannot serve either:

1. **Feasibility.** A brief that cannot fit a model's hard `contextLimit` fails
   with `stopReason: "length"`, which
   [Specify the Pi work-unit protocol](05-specify-the-pi-work-unit-protocol.md)
   classes as a quality failure. Without a pre-dispatch check, Fleet spends the
   job's one quality attempt on work that was never runnable. This is the
   estimator's primary justification, and it applies to every model.
2. **Cost hygiene.** Qwen3.7 Plus prices differently above 256K, and
   [Specify routing and evaluation mechanics](04-specify-routing-and-evaluation-mechanics.md)
   forbids silently entering the higher band because it contaminates the cost
   evidence a cohort exists to produce.

It is explicitly **not** an input to model evaluation. That is the routing
evidence log, which measures outcomes after the fact from real usage.

### Why crude is correct

The estimator is allowed to be quite wrong, in either direction, because both
errors are cheap:

- **Over-count** — a model is needlessly ineligible; rotation picks another in
  the same tier. Cost: a marginally worse pick.
- **Under-count** — the run crosses the band or exhausts context; the crossing
  is detected from real summed usage and excluded from the cohort, or the
  `length` failure escalates. Cost: one contaminated or spent attempt, rarely.

Precision therefore buys nothing. A projected-peak estimator — per-role growth
allowances, per-family calibrated divisors, a probed harness-overhead constant —
was designed and **rejected**: it is substantial apparatus in service of a
number whose errors are both inexpensive, and every part of it would itself need
maintaining against Pi and provider changes.

### Method

Estimated input is `ceil(utf8Bytes / 3.5)` over exactly what Fleet assembles for
that stage: the role brief, the job's immutable input snapshot, the verbatim
sealed artifacts of the depended-on stages, and the repository's own
AGENTS.md/CLAUDE.md context files, which Fleet counts directly because it can
read them.

No tokenizer is bundled. An exact count in the wrong vocabulary is false
precision — Qwen and DeepSeek do not share a tokenizer, so a bundled one would
be authoritative for neither. The 3.5 divisor over-counts prose and roughly
tracks code, which is the safe direction for a feasibility check.

**Not counted**, by design: Pi's default system prompt, the tool schemas for the
role's `--tools` allowlist and the Fleet extension's `submit_*`/`raise_risk`
declarations, loaded skills and prompt templates, and all context growth from
`read`, `grep`, and bash results during the stage. The margin absorbs them.

The estimate is per **stage dispatch**, not per job — each stage assembles its
own brief, and a writing brief carrying large sealed artifacts can exceed a
scouting brief substantially.

### The margin

A model is eligible while `estimatedInput <= 0.5 * limit`, where `limit` is the
band threshold for a model that has one and the hard `contextLimit` otherwise.

A ratio rather than fixed headroom, so one knob generalises across every model
without a second config surface. 50% is loose deliberately: it is the slack that
covers everything the method above declines to count, and ticket 04's own
observation that real work rarely approaches 200K means the guard almost never
fires, so a loose margin costs close to nothing while a tight one would produce
needless ineligibility.

### Calibration

Every attempt record carries `estimatedInput` alongside the true summed `input`
from the event stream. The divisor is then a `fleet-update` correction backed by
recorded evidence rather than a constant someone guessed once — the same
treatment ticket 04 gives prices.

This **extends** ticket 04's overlay, which permitted only `tier`, `enabled`,
`roles`, and price corrections: the overlay additionally carries an optional
per-family divisor. Ticket 04's principle is unchanged — `fleet-update` writes
only the overlay, never the shipped registry.

### When nothing fits

A brief exceeding the margin for every eligible model returns to the primary
orchestrator with a typed `input-too-large` reason, alongside
`provider-unavailable`.

Truncating the snapshot or the depended-on sealed artifacts was rejected: it
silently degrades the input the stage is contracted to work from, and the
resulting failure is then indistinguishable from a model that was simply not
good enough — contaminating exactly the quality evidence Fleet collects.
Escalating a tier to buy a larger window was also rejected: it spends premium
money to paper over a mis-sized job rather than a hard one.

### Band violation

A run that crosses its band mid-stage is detected **after the fact**, from the
usage summed across every assistant message, and recorded as a **band
violation** on the attempt: excluded from the cost cohort, and a `fleet-update`
signal that the divisor or the margin is too loose.

Live abort on the streamed usage was rejected. Usage arrives per assistant
message, so by the time Fleet observes the crossing the higher-band request is
already billed — aborting discards work already paid for and saves nothing.

This is the entire safety net behind a deliberately crude estimator, which is
what licenses the crudeness.

### Vocabulary

Added **Estimated input** and **Band violation** to `fleet/CONTEXT.md`. The
first exists to stop a future reader treating the estimate as a measurement; the
second names a condition ticket 04 implied but never named.
