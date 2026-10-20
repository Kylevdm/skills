#!/usr/bin/env bash
# cost.sh: total cost per model across several pi run logs (a batch, a bake off).
#
#   cost.sh <run.pi.jsonl>...
#
# OpenCode Go figures count against the Go allowance; OpenAI figures are
# notional (ChatGPT Plus is flat-rate). Runs that ended on an error are listed.
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: cost.sh <run.pi.jsonl>..." >&2; exit 2; }

for log in "$@"; do
  jq -c --arg log "$(basename "$log" .pi.jsonl)" \
    'select(.type == "message_end" and .message.role == "assistant") | .message
     | {log: $log, model: "\(.provider)/\(.model)", cost: (.usage.cost.total // 0), stop: .stopReason}' "$log"
done | jq -rs '
  (group_by(.log)[] | "\(.[0].log)\t\(.[0].model)\t$\([.[].cost] | add | . * 100 | round / 100)\(if .[-1].stop == "error" then "\tENDED ON ERROR" else "" end)"),
  "",
  (group_by(.model)[] | "total\t\(.[0].model)\t$\([.[].cost] | add | . * 100 | round / 100)")
' | column -t -s $'\t'
