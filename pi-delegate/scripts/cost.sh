#!/usr/bin/env bash
# cost.sh: cost and Go allowance used, per run and per model, across pi run logs.
#
#   cost.sh <run.pi.jsonl>...
#
# Allowance is spend / the model's monthly Go limit (assets/go-limits.tsv),
# summed across models: 5 h window = 20%, week = 50%, month = 100%. OpenAI
# figures are notional (ChatGPT Plus is flat-rate) and use no Go allowance.
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: cost.sh <run.pi.jsonl>..." >&2; exit 2; }
LIMITS=$(dirname "$0")/../assets/go-limits.tsv

for log in "$@"; do
  jq -c --arg log "$(basename "$log" .pi.jsonl)" \
    'select(.type == "message_end" and .message.role == "assistant") | .message
     | {log: $log, provider, model, cost: (.usage.cost.total // 0), stop: .stopReason}' "$log"
done | jq -rs --rawfile limits "$LIMITS" '
  ($limits | split("\n") | map(select(length > 0 and (startswith("#") | not)) | split("\t"))
    | map({(.[0]): .[1]}) | add) as $lim
  | def allowance: if .provider != "opencode-go" then "-"
      elif $lim[.model] == null then "limit unknown"
      elif $lim[.model] == "free" then "0%"
      else "\((.cost / ($lim[.model] | tonumber) * 1000 | round) / 10)%" end;
  def money: . * 100 | round / 100;
  def runs: group_by(.log)[] | {log: .[0].log, provider: .[0].provider, model: .[0].model,
      cost: ([.[].cost] | add), error: (.[-1].stop == "error")};
  [runs] as $runs
  | "run\tmodel\tcost\tallowance",
    ($runs[] | "\(.log)\t\(.provider)/\(.model)\t$\(.cost | money)\t\(allowance)\(if .error then "\tENDED ON ERROR" else "" end)"),
    "",
    ($runs | group_by("\(.provider)/\(.model)")[]
      | {provider: .[0].provider, model: .[0].model, cost: ([.[].cost] | add)}
      | "total\t\(.provider)/\(.model)\t$\(.cost | money)\t\(allowance)"),
    "go allowance\t\t\t\([$runs[] | select(.provider == "opencode-go" and ($lim[.model] // "free") != "free")
      | .cost / ($lim[.model] | tonumber)] | add // 0 | . * 1000 | round / 10)%"
' | column -t -s $'\t'
