# OpenCode Go models off the roster

- **Checked:** 2026-10-25. Prices, limits and benchmark tables change often; recheck before acting on any row.
- **Scope:** Go models with a $60+ monthly limit in [assets/go-limits.tsv](../assets/go-limits.tsv)
  (checked 2026-10-20) that are not on the roster, plus `longcat-2.5-preview-free`. Roster models
  (glm-5.2, kimi-k2.7-code, deepseek-v4.1-flash) appear only for comparison.
- **Evidence ranking:** independent leaderboard > OpenCode's own data > vendor card or blog (marked
  **vendor**) > secondary write-ups (marked **secondary**, used only when nothing else exists).
  "Not found" means no primary source had it.
- **Leaderboards used:** [DeepSWE v1.1](https://deepswe.datacurve.ai/) (113 tasks, all models on
  mini-swe-agent, updated 2026-09-22) and [Terminal-Bench 4.0](https://www.tbench.ai/leaderboard)
  (the only version the site shows now). [swebench.com](https://www.swebench.com/) (latest entry
  2026-02) and [aider.chat](https://aider.chat/docs/leaderboards/) (latest 2025-10) list none of
  these models.
- **Verdicts:** *trial-implement*, *trial-review*, *trial-mechanical*, *trial-sweeps* (run it as an
  extra contestant or reviewer under SKILL.md "Trying new models"), or *skip*. The roster stays the
  user's decision.
- **Our runs:** aggregates from `~/.local/share/pi-delegate/runs.jsonl`. Every n is 1 or 2, so treat
  them as anecdotes, not rates. Allowance is the fraction of the monthly Go allowance (0.0047 = 0.47%).

## The Go page has changed since go-limits.tsv (2026-10-20)

The [Go docs](https://opencode.ai/v2/docs/console/go/) as fetched on 2026-10-25 differ from
`go-limits.tsv` for three of the models in scope. Refresh the table before the next run.

| Model | go-limits.tsv | Go page on 2026-10-25 |
|---|---|---|
| step-5-preview | $60 ("4x for a limited time; normally 15") | **$15**: the promotion has ended, so `run.sh` would now refuse it |
| gemini-4-argon-contributor | $60 ("2x for a limited time; normally 30") | **Not listed.** Only `gemini-4-argon` at **$30**, with tokens 50% off "through November 30, 2026" |
| longcat-2.5-preview-free | free | **Not listed.** `beam-free` ("Free for a limited time", limited regions) appears instead |

New on the page and not covered here: kimi-k3.1-pro ($15), minimax-m3.1-flash ($20), and hy4-preview ($30).

## Summary

| Model | Go limit | Context / max out | Strengths (claimed) | Best benchmark evidence | Our runs | Verdict |
|---|---|---|---|---|---|---|
| glm-5.3-flash | $60 | 1M / 131K | efficient coding, long-horizon agents | **DeepSWE leaderboard 63% ±4 at $0.24/task** (glm-5.2: 44%); **TB 4.0 leaderboard 35.8%** | impl 2× fixed-small (0.17–0.47%); review 1/4 real | **trial-implement** (needs the user's OK: dropped as a *reviewer* 2026-10-25) |
| longcat-2.0 | $60 | 1M / 131K | repo-level coding, agents | vendor: SWE-bench Pro 59.5, TB 2.1 70.8 | none | **trial-review** (low priority) |
| step-5-preview | **now $15** (was a $60 promo) | 1M / 1M (card is inconsistent) | SWE, long-horizon agents | vendor: TB 4.0 33.3, DeepSWE 67.7 | review 2× (3/5 real; 1 provider reject); 1.0–1.2% each at $60, ~4–5% at $15 | **skip** (end the trial: $15 limit) |
| mimo-v2.6-flash | $60 | 1M / 131K | coding agents, tool use, cheap | vendor: DeepSWE 67.9, TB 2.1 87.6, TB 4.0 28.8 | impl 1× fixed-small (0.07%, 36 min) | **trial-implement / trial-mechanical** (continue) |
| mimo-v2.5 | $60 | 1M / 131K | multimodal agents | vendor: SWE-bench Pro 56.1, TB 2.0 65.8 | none | **skip** (v2.6-flash, same price, replaces it) |
| minimax-m3 | $60 | 1M / 512K | long-context coding, speed | vendor: SWE-bench Verified 80.5, Pro 59.0, TB 2.1 66.0 | impl 1× rejected (provider); review 3/6 real at 1.39% | **skip** (dropped 2026-10-25) |
| muse-spark-1.3-contributor | $60 | 1M / 131K | agentic coding, efficiency | **TB 4.0 leaderboard 14.5%** (Muse Code, xhigh); vendor DeepSWE 75.4 (max) | none | **skip**: prompts and completions **train Meta models**, not ZDR |
| muse-spark-1.2-contributor | $60 | 1M / 131K | coding, debugging | **DeepSWE leaderboard 55% ±2** (xhigh) | none | **skip**: same data-use terms; 1.3 supersedes it |
| qwen3.7-plus | $60 | 1M / 131K (Alibaba) or 64K (OpenCode) | multimodal agent, GUI, coding | vendor: none found; secondary only | impl 1× rerun (model) | **skip** (dropped 2026-10-25) |
| hy3 | $60 | 256K / 128K | coding, tool use, cheap | vendor: SWE-bench Verified 78, Pro 57.9, DeepSWE **28** | none | **skip** (weak DeepSWE, short context) |
| gemini-4-argon(-contributor) | **now $30** (contributor variant gone) | 1M combined / 65K default | SWE, long context, agents | vendor: DeepSWE 77.9, TB 4.0 57.4, GraphWalks 1M 84.2 | none | **skip on Go** (not $60; $2/$10 tokens) |
| longcat-2.5-preview-free | free (**no longer listed**) | 1M / 131K | coding, image input | none published | not in the log | roster prototype slot; **check it still works** |

Roster comparison: deepseek-v4.1-flash (vendor DeepSWE 74.2, TB 2.1 90.6, TB 4.0 31.2; not on
either leaderboard; its predecessor deepseek-v4-flash scores 53% on DeepSWE) took 73 of 80 real
findings in 8 reviews, at a median allowance of 0.12% per review. glm-5.2 scores 44% on the DeepSWE
leaderboard (vendor TB 2.1: 82.7) and costs a median of 1.79% of the allowance per implementation.

---

## glm-5.3-flash (Z.ai)

- **What:** an open-weight MoE (MIT), 320B total and 18B active, with hybrid sparse and linear
  attention. It is "the first natively multimodal model in the GLM-5 series" and has a
  `reasoning_effort` of low, high or max ([HF card](https://huggingface.co/zai-org/GLM-5.3-Flash)).
  Released 2026-08-26 ([OpenCode data](https://opencode.ai/data/zhipuai/glm-5-3-flash)).
- **Context / output:** 1M / 131,072 (OpenCode data). The HF card gives no spec, only eval settings
  such as a "1M context" for NL2Repo.
- **Price (Go):** $0.15 in, $0.50 out, $0.03 cached per 1M tokens, against glm-5.2's $1.40 / $4.40
  ([Go docs](https://opencode.ai/v2/docs/console/go/)), so about a ninth of glm-5.2 per token at
  the same $60 limit.
- **Claimed:** "outperforms GLM-5.2 across benchmarks", "approaching Claude Opus 4.8 on coding and
  agentic benchmarks" (HF card, **vendor**).
- **Benchmarks:**
  - **DeepSWE v1.1 leaderboard: 63% ±4 (max), $0.24 per task, 123 steps.** For comparison, glm-5.2
    scores 44% ±2 at $3.92 and deepseek-v4-flash 53% ±4 ([DeepSWE](https://deepswe.datacurve.ai/), updated 2026-09-22).
  - **Terminal-Bench 4.0 leaderboard: 35.8% ±3.5** (Claude Code, effort none, rank 23; 2026-08-26).
    GLM-5.3 at max scored 41.8% ([tbench.ai](https://www.tbench.ai/leaderboard)).
  - **Vendor:** TB 2.1 84.3, DeepSWE 63.4, Agents' Last Exam 26.3, AutomationBench 48.8 (HF card;
    OpenCode data).
- **Our runs:** 2 trial-implement runs, both fixed-small, at 0.17% and 0.47% (glm-5.2's
  implementation median is 1.79%). 2 trial-reviews found 1 real finding out of 4. Dropped as a
  reviewer on 2026-10-25; it has never been rejected as an implementer.
- **Verdict:** **trial-implement**, shadowing glm-5.2. It has the strongest independent evidence of
  any candidate and costs far less allowance. The user dropped it for reviews, so ask before
  re-trialling it for implementation.

## longcat-2.0 (Meituan)

- **What:** an open-weight MoE (MIT), 1.6T total and about 48B active, plus 135B N-gram embedding
  parameters; the safetensors metadata says 1.8T
  ([HF card](https://huggingface.co/meituan-longcat/LongCat-2.0)). Released 2026-06-30
  ([OpenCode data](https://opencode.ai/data/meituan/longcat-2-0)).
- **Context / output:** 1M / 131,072 (OpenCode data). The card says it was trained on 1M-context data.
- **Price (Go):** $0.30 in, $1.20 out, $0.006 cached (Go docs), the same tokens as deepseek-v4.1-flash
  at peak. Its limit is $60 against deepseek's $80, so about 1.33× deepseek's allowance at peak.
- **Claimed:** coding, repository-level edits, agentic tasks (HF card).
- **Benchmarks (vendor, "measured in-house under a unified harness"):** TB 2.1 70.8, SWE-bench Pro
  59.5, SWE-bench Multilingual 77.3, BrowseComp 79.9, IFEval 90.0 (HF card). It is on neither
  leaderboard.
- **Our runs:** none.
- **Verdict:** **trial-review**, low priority, as an extra reviewer beside deepseek-v4.1-flash. It
  is untested here and has only vendor numbers.

## step-5-preview (StepFun)

- **Limit:** the Go page **now lists $15** (Go) / $60 (Go Plus). The $60 "4x for a limited time"
  entry in go-limits.tsv has expired.
- **What:** an open-weight sparse MoE, 600B total and 27B active, under the StepFun Model License 1.0
  ("Apache-2.0-Style … with additional attribution and commercial-license conditions")
  ([HF card](https://huggingface.co/stepfun-ai/Step-5-Preview)). Released 2026-09-16
  ([OpenCode data](https://opencode.ai/data/stepfun/step-5-preview)).
- **Context / output:** the card says "Up to 1M tokens" for both, but also that "The 1M-token context
  limit covers input and output combined".
- **Price (Go):** $1.00 in, $2.70 out, $0.10 cached.
- **Claimed:** repository-level SWE, long-horizon agentic execution, and knowledge work (HF card).
- **Benchmarks (vendor):** Terminal-Bench 4.0 33.3, DeepSWE 67.7*, ALE CLI 29.5* (HF card; the
  asterisks are unexplained). The main chart is an image. It is not on either leaderboard.
- **Our runs:** 2 trial-reviews, logged at the $60 limit: one found 3 real findings out of 5 (1.2%),
  the other was rejected for a provider fault (0.97%). At $15 the same spend would cost about 4.8%
  and 3.9%, far above deepseek-v4.1-flash's 0.12% median.
- **Verdict:** **skip**. End the current reviewer trial, because $15 models are on the avoid list
  and `run.sh` refuses them.

## mimo-v2.6-flash (Xiaomi)

- **What:** an open-weight sparse MoE (MIT), 309B total and 15B active. It takes text, image, video
  and audio input
  ([HF card, MiMo-V2.6-Flash-RL](https://huggingface.co/XiaomiMiMo/MiMo-V2.6-Flash-RL)). Released
  2026-09-22 ([OpenCode data](https://opencode.ai/data/xiaomi/mimo-v2-6-flash)). The open checkpoint
  is named "-RL"; no primary source confirms it is identical to the API model.
- **Context / output:** 1M (card) / 131,072 (OpenCode data).
- **Price (Go):** $0.14 in, $0.28 out, $0.0028 cached, the cheapest output of any $60 model except Muse.
- **Benchmarks (vendor):** DeepSWE v1.1 67.9, TB 2.1 87.6, TB 4.0 28.8, Toolathlon-Verified 73.6,
  ProgramBench 26.0 (HF card). It is on neither leaderboard.
- **OpenCode usage:** #5 by tokens last week, with 82.6% weekly retention, the highest of the models
  here (OpenCode data). That is a popularity signal, not a quality measure.
- **Our runs:** 1 trial-implement, fixed-small, at 0.07% of the allowance, but it took 36 minutes of wall time.
- **Verdict:** **trial-implement / trial-mechanical**. Continue the current trial, shadowing
  glm-5.2 on fixes or kimi-k2.7-code on mechanical work. Watch the wall time.

## mimo-v2.5 (Xiaomi)

- **What:** an open-weight sparse MoE (MIT), 310B total and 15B active
  ([HF card](https://huggingface.co/XiaomiMiMo/MiMo-V2.5)). Released 2026-04-22
  ([OpenCode data](https://opencode.ai/data/xiaomi/mimo-v2-5)).
- **Context / output:** 1M / 131,072.
- **Price (Go):** the same as v2.6-flash.
- **Benchmarks (vendor):** SWE-bench Pro 56.1, TB 2.0 65.8 (HF card). The v2.6-flash card reports
  V2.5-**Pro** at DeepSWE 19.0 and TB 2.1 65.2. It is on neither leaderboard.
- **Our runs:** none.
- **Verdict:** **skip**. It is an older generation at the same price as mimo-v2.6-flash.

## minimax-m3 (MiniMax)

- **What:** a MoE of about 428B total and 23B active with MiniMax Sparse Attention, under the
  "minimax-community" license, with thinking modes enabled, adaptive and disabled
  ([HF card](https://huggingface.co/MiniMaxAI/MiniMax-M3)). Released 2026-06-01
  ([MiniMax blog](https://www.minimax.io/blog/minimax-m3)).
- **Context / output:** 1M / 512K (OpenCode data).
- **Price (Go):** $0.30 in, $1.20 out, $0.06 cached.
- **Claimed:** 9× faster prefill and 15× faster decode than M2 at 1M context (blog, **vendor**).
- **Benchmarks (vendor):** SWE-bench Verified 80.5, SWE-bench Pro 59.0 (Claude Code, internal
  infra), TB 2.1 66.0 (Terminus 2), MCP Atlas 74.2 (blog). It is on neither leaderboard.
- **Our runs:** 1 trial-implement, rejected for a provider fault (0.31%). 1 trial-review found 3
  real out of 6, at 1.39%, more than glm-5.2's review median of 0.94%.
- **Verdict:** **skip**. Dropped at the user's say-so on 2026-10-25.

## muse-spark-1.3-contributor (Meta)

- **Data use:** the Go docs say "Heavily discounted token pricing in exchange for permission to use
  your prompts and completions to train future Meta models", Training "Yes", retention "Not ZDR". It
  is disabled by default: an admin must turn on "Allow paid endpoints that train on request data".
  Every brief and diff we send would become Meta training data.
- **What:** Meta's closed model. Released 2026-09-02
  ([Meta blog](https://research.meta.ai/blog/introducing-muse-spark-1-3)). Architecture: not found.
- **Context / output:** 1,048,576 / 131,072 (OpenCode data).
- **Price (Go):** $0.10 in, $0.20 out.
- **Claimed:** about 20% fewer tool calls and 25% fewer tokens than 1.2 (Meta blog, **vendor**).
  "Max reasoning" arrived after the xhigh launch (secondary:
  [propakistani](https://propakistani.pk/2026/09/03/meta-launches-muse-spark-1-3-with-faster-coding-and-smarter-agents/)).
  Which effort level Go serves: not found.
- **Benchmarks:**
  - **Terminal-Bench 4.0 leaderboard: 14.5% ±2.9** (Muse Code, xhigh, rank 32; 2026-09-02).
  - **Vendor (max effort):** DeepSWE 75.4, TB 2.1 88.8, SWE-Atlas QnA 59.4, MRCR 98.5 (OpenCode data,
    citing the Meta blog). 1.3 is not on the DeepSWE board.
- **OpenCode usage:** #4 by tokens, with 21% of all Go tokens.
- **Our runs:** none.
- **Verdict:** **skip**. Code would go to training, and the independent TB 4.0 score is low. Revisit
  only if the user explicitly accepts that data use, and then only for public repositories.

## muse-spark-1.2-contributor (Meta)

- **What / terms:** the same contributor terms as 1.3. Released 2026-08-05
  ([OpenCode data](https://opencode.ai/data/meta/muse-spark-1-2-contributor)). It is the default
  model of Meta's Muse Code ([docs](https://dev.meta.ai/docs/muse-code)).
- **Context / output:** 1,048,576 / 131,072.
- **Price (Go):** $0.10 in, $0.20 out.
- **Benchmarks:** **DeepSWE leaderboard 55% ±2** (xhigh, $3.70 per task at list price). Vendor:
  TB 2.1 82.9, MCP Atlas 90.3 (OpenCode data, citing Meta).
- **Our runs:** none.
- **Verdict:** **skip**.

## qwen3.7-plus (Alibaba)

- **What:** Alibaba's closed multimodal agent model. Its snapshot is `qwen3.7-plus-2026-05-26`
  ([Alibaba Model Studio](https://help.aliyun.com/en/model-studio/qwen3-7-plus-us)).
  Architecture: not found.
- **Context / output:** 1,000,000 context, 991,808 input, and 131,072 output (Alibaba). OpenCode data
  says 64,000 output.
- **Price (Go):** $0.40 in, $1.60 out up to 256K input; $1.20 / $4.80 above 256K.
- **Benchmarks:** vendor numbers not found. Secondary only:
  [BenchLM](https://www.benchlm.ai/models/qwen3-7-plus) lists TB 2.0 70.3 and SWE-bench Pro 57.6.
  It is on neither leaderboard.
- **Our runs:** 1 trial-implement, a rerun caused by the model.
- **Verdict:** **skip**. Dropped at the user's say-so on 2026-10-25 for weak implementation.

## hy3 (Tencent)

- **What:** an open-weight MoE (Apache 2.0), 295B total and 21B active, with 192 experts (top-8)
  ([HF card](https://huggingface.co/tencent/Hy3)). Released 2026-07-06
  ([OpenCode data](https://opencode.ai/data/tencent/hy3)).
- **Context / output:** **256K** / 128K.
- **Price (Go):** $0.14 in, $0.58 out, $0.035 cached.
- **Benchmarks (vendor):** SWE-bench Verified 78, SWE-bench Pro 57.9, TB 2.1 71.7*, **DeepSWE 28**,
  MCP Atlas 79.1 (HF card). In a blind test by 270 experts it scored 2.67/4 against GLM-5.1's 2.51.
  It is on neither leaderboard.
- **Our runs:** none.
- **Verdict:** **skip**. Its own DeepSWE score is low, and 256K is too short for large-context sweeps.

## gemini-4-argon-contributor / gemini-4-argon (Google)

- **Limit:** the contributor variant is **not on the Go page**. `gemini-4-argon` is listed at a $30
  limit, with tokens at $2.00 in and $10.00 out (50% off "through November 30, 2026"). What the
  contributor terms were: not found.
- **What:** Google's closed sparse MoE, "flagship reasoning model". Published 2026-10-13
  ([DeepMind model card](https://deepmind.google/models/model-cards/gemini-4-argon/)).
- **Context / output:** 1,048,576 shared between input and output; 65,536 output by default, up to
  1,048,576 "with long decode" ([Gemini API docs](https://ai.google.dev/gemini-api/docs/models/gemini-4-argon)).
- **Benchmarks (vendor, model card):** DeepSWE v1.1 77.9 (GPT-6 Astra 74.1), TB 4.0 57.4 (Astra
  58.2), FrontierSWE v2 55.0 (Astra 65.5), GraphWalks 256K–1M 84.2. It is not on either
  leaderboard yet: it was released after the DeepSWE board's last update.
- **Our runs:** none.
- **Verdict:** **skip on Go**. A $30 limit and $10 output per 1M tokens make it about 40× glm-5.3-flash's
  allowance cost per output token. Recheck if a $60 or contributor variant comes back, and weigh the
  contributor data terms as for Muse.

## longcat-2.5-preview-free (Meituan), brief

- **Status:** this is the roster's "throwaway prototypes" model, but it is **no longer on the Go page**
  (2026-10-25). OpenCode data still has a page for it, with average cost per session $0, #11 by tokens
  ([OpenCode data](https://opencode.ai/data/meituan/longcat-2-5-preview)).
- **What:** closed, released 2026-09-25, 1M / 131,072, with image input. Architecture, benchmarks
  and model card: not found. A secondary source says Meituan published none
  ([benchmarklist](https://benchmarklist.com/models/meituan-longcat-2.5-preview/), secondary).
- **Our runs:** none in the log.
- **Action:** confirm the model id still works before the next prototype run. If it doesn't,
  `beam-free` is the free replacement on the Go page; nothing is known about it.

## Recommended next trials

These follow SKILL.md: at most one trial per task or wave, only while the 5-hour window is at 10%
or less, never on protected paths or Never-change items, and the result is merged only if it beats
the roster model in review.

1. **glm-5.3-flash, implement, shadowing glm-5.2** on S/M fixes. It is the only candidate with
   independent evidence: DeepSWE 63% against glm-5.2's 44%, at about 1/16 the cost per task, and
   TB 4.0 35.8%. Its 2 local implementations were both fixed-small, at a quarter or less of glm-5.2's
   median allowance. **Ask the user first:** it was dropped on 2026-10-25, though as a reviewer,
   not as an implementer.
2. **mimo-v2.6-flash, implement or mechanical, shadowing glm-5.2 or kimi-k2.7-code.** It is already
   in the trial group with 1 fixed-small run at 0.07%. Get it to 5 records. The cost risk is low;
   the risks are the 36-minute wall time and having only vendor numbers.
3. **longcat-2.0, extra reviewer, beside deepseek-v4.1-flash** (spec and sweep reviews). It is
   untested here, has a $60 limit and 1M context, and has the best vendor SWE-bench Pro score of
   the untested candidates (59.5). The bar is high: deepseek found 73 real of 80 at 0.12% per review.

Stop the step-5-preview reviewer trial (now $15). Muse Spark stays out unless the user accepts the
training-data terms.

## Sources

- OpenCode Go docs (limits, prices, privacy), fetched 2026-10-25: https://opencode.ai/v2/docs/console/go/
- OpenCode model data (release date, context, output, usage, cited benchmarks), updated 2026-10-25:
  https://opencode.ai/data/zhipuai/glm-5-3-flash, https://opencode.ai/data/meituan/longcat-2-0,
  https://opencode.ai/data/meituan/longcat-2-5-preview, https://opencode.ai/data/stepfun/step-5-preview,
  https://opencode.ai/data/xiaomi/mimo-v2-6-flash, https://opencode.ai/data/xiaomi/mimo-v2-5,
  https://opencode.ai/data/minimax/minimax-m3, https://opencode.ai/data/meta/muse-spark-1-3-contributor,
  https://opencode.ai/data/meta/muse-spark-1-2-contributor, https://opencode.ai/data/alibaba/qwen3-7-plus,
  https://opencode.ai/data/tencent/hy3, https://opencode.ai/data/google/gemini-4-argon
- DeepSWE v1.1 leaderboard (updated 2026-09-22): https://deepswe.datacurve.ai/
- Terminal-Bench 4.0 leaderboard: https://www.tbench.ai/leaderboard
- SWE-bench (no covered models): https://www.swebench.com/ · Aider (no covered models): https://aider.chat/docs/leaderboards/
- Vendor cards and posts: https://huggingface.co/zai-org/GLM-5.3-Flash ·
  https://huggingface.co/meituan-longcat/LongCat-2.0 · https://huggingface.co/stepfun-ai/Step-5-Preview ·
  https://huggingface.co/XiaomiMiMo/MiMo-V2.6-Flash-RL · https://huggingface.co/XiaomiMiMo/MiMo-V2.5 ·
  https://huggingface.co/MiniMaxAI/MiniMax-M3 · https://www.minimax.io/blog/minimax-m3 ·
  https://research.meta.ai/blog/introducing-muse-spark-1-3 · https://dev.meta.ai/docs/muse-code ·
  https://help.aliyun.com/en/model-studio/qwen3-7-plus-us · https://huggingface.co/tencent/Hy3 ·
  https://deepmind.google/models/model-cards/gemini-4-argon/ ·
  https://ai.google.dev/gemini-api/docs/models/gemini-4-argon
- Secondary (labelled where used): https://www.benchlm.ai/models/qwen3-7-plus ·
  https://benchmarklist.com/models/meituan-longcat-2.5-preview/ ·
  https://propakistani.pk/2026/09/03/meta-launches-muse-spark-1-3-with-faster-coding-and-smarter-agents/
- Local: `~/.local/share/pi-delegate/runs.jsonl` (109 records, read 2026-10-25)
