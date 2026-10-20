#!/usr/bin/env bash
# summarize.sh: one-screen summary of a pi --mode json run log.
#
#   summarize.sh <run.pi.jsonl> [start-epoch]
#
# Prints model, turns, tool calls (and errors), tokens, cost per model and the
# final assistant text. With a start epoch (date +%s at launch) it also prints
# wall time, measured to the log's last write.
set -euo pipefail

LOG=${1:?usage: summarize.sh <run.pi.jsonl> [start-epoch]}
START=${2:-}

jq -rs '
  def assistant: .[] | select(.type == "message_end" and .message.role == "assistant") | .message;
  [assistant] as $a
  | [.[] | select(.type == "tool_execution_end")] as $t
  | "models:      \([$a[] | "\(.provider)/\(.model)"] | unique | join(", "))",
    "turns:       \($a | length)  (last stop: \($a[-1].stopReason // "none"))",
    "tool calls:  \($t | length)  (errors: \([$t[] | select(.isError)] | length))",
    "tokens:      \([$a[].usage.totalTokens // 0] | add // 0) total, \([$a[].usage.output // 0] | add // 0) output",
    ( $a | group_by("\(.provider)/\(.model)")[]
      | "cost:        \(.[0].provider)/\(.[0].model) $\([.[].usage.cost.total // 0] | add | . * 10000 | round / 10000)" ),
    "aborted:     \([.[] | select(.type == "agent_end")] | if length == 0 then "no agent_end (run cut short?)" else (.[0].aborted == true | tostring) end)",
    "",
    "--- final message ---",
    ([$a[] | .content[]? | select(.type == "text") | .text] | last // "(no text)")
' "$LOG"

if [ -n "$START" ]; then
  END=$(stat -c %Y "$LOG")
  echo
  echo "wall time:   $(( (END - START) / 60 ))m $(( (END - START) % 60 ))s"
fi
