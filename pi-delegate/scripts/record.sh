#!/usr/bin/env bash
# record.sh: the delegation benchmark, one anonymised record per pi run.
#
#   record.sh add <run.pi.jsonl> <start-epoch> <repo-label> [log-label]
#                                                              append a run's metrics (run.sh does this)
#   record.sh set <id> key=value...                            add review outcomes to a record
#   record.sh show [n]                                         print the last n records (default 10)
#
# Records live in ${PI_DELEGATE_RUNS:-~/.local/share/pi-delegate/runs.jsonl}, outside
# any repo. They hold metrics and labels only: never code, brief text, paths or output.
# Outcome keys (set after review; see SKILL.md "Benchmark"):
#   role=implement|review|trial-implement|trial-review|prototype  brief=single|batch
#   issue=<n>  task=feature|fix|tests|refactor|review|docs  size=S|M|L
#   files=<n>  lines=<n> (changed, added+deleted; size S < 150, M < 500, L >= 500)
#   risk=low|medium|high  touched_safety=true|false  attempt=<n>
#   outcome=merged|fixed-small|rerun|rejected  findings_real=<n>  findings_total=<n>
#   safety_relaxed=true|false  backfilled=<comma-separated keys>
# Values that parse as JSON (numbers, true/false) are stored as such; the rest as strings.
set -euo pipefail

RUNS=${PI_DELEGATE_RUNS:-$HOME/.local/share/pi-delegate/runs.jsonl}
LIMITS=$(dirname "$0")/../assets/go-limits.tsv
mkdir -p "$(dirname "$RUNS")"; touch "$RUNS"

case "${1:-}" in
  add)
    [ $# -ge 4 ] && [ $# -le 5 ] || {
      echo "usage: record.sh add <run.pi.jsonl> <start-epoch> <repo-label> [log-label]" >&2; exit 2; }
    LOG=$2; START=$3; REPO=$4; LABEL=${5:-$(basename "$LOG" .pi.jsonl)}
    END=$(stat -c %Y "$LOG")
    jq -cs --arg log "$LABEL" --arg repo "$REPO" \
      --argjson start "$START" --argjson end "$END" --rawfile limits "$LIMITS" '
      ($limits | split("\n") | map(select(length > 0 and (startswith("#") | not)) | split("\t"))
        | map({(.[0]): .[1]}) | add) as $lim
      | [.[] | select(.type == "message_end" and .message.role == "assistant") | .message] as $a
      | [.[] | select(.type == "tool_execution_end")] as $t
      | ($a[0].provider // "unknown") as $provider | ($a[0].model // "unknown") as $model
      | ([$a[].usage.cost.total // 0] | add // 0) as $cost
      | ($a[-1].errorMessage // null) as $err
      | {
          id: "\($repo)/\($log)@\($start)",
          started: ($start | todate), repo: $repo, log: $log,
          provider: $provider, model: $model,
          wall_s: ($end - $start), turns: ($a | length),
          tool_calls: ($t | length), tool_errors: ([$t[] | select(.isError)] | length),
          tokens: ([$a[].usage.totalTokens // 0] | add // 0),
          cost_usd: ($cost * 10000 | round / 10000),
          allowance: (if $provider != "opencode-go" then null
                      elif $lim[$model] == "free" then 0
                      elif $lim[$model] == null then null
                      else ($cost / ($lim[$model] | tonumber) * 10000 | round / 10000) end),
          error: (if ($a[-1].stopReason // "none") != "error" then null
                  elif ($err // "" | test("GoUsageLimit")) then "go_usage_limit"
                  elif ($err // "" | test("429|rate.?limit"; "i")) then "rate_limit"
                  else "other" end)
        }' "$LOG" | tee -a "$RUNS" | jq -r '"recorded \(.id)"'
    ;;
  set)
    [ $# -ge 3 ] || { echo "usage: record.sh set <id> key=value..." >&2; exit 2; }
    ID=$2; shift 2
    grep -qF "\"id\":\"$ID\"" "$RUNS" || { echo "record.sh: no record $ID" >&2; exit 2; }
    patch='{}'
    for kv in "$@"; do
      k=${kv%%=*}; v=${kv#*=}
      [ "$k" != "$kv" ] || { echo "record.sh: expected key=value, got $kv" >&2; exit 2; }
      if [ "$k" = backfilled ]; then
        patch=$(jq -c --arg v "$v" '.backfilled = ($v | split(","))' <<<"$patch")
      elif jq . >/dev/null 2>&1 <<<"$v"; then
        patch=$(jq -c --arg k "$k" --argjson v "$v" '.[$k] = $v' <<<"$patch")
      else
        patch=$(jq -c --arg k "$k" --arg v "$v" '.[$k] = $v' <<<"$patch")
      fi
    done
    tmp=$(mktemp "$RUNS.XXXX")
    jq -c --arg id "$ID" --argjson p "$patch" 'if .id == $id then . + $p else . end' "$RUNS" >"$tmp"
    mv "$tmp" "$RUNS"
    echo "updated $ID"
    ;;
  show)
    tail -n "${2:-10}" "$RUNS" | jq -c .
    ;;
  *)
    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
