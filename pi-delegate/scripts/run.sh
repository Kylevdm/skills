#!/usr/bin/env bash
# run.sh: run one delegated pi task inside pi-jail and log it next to the worktree.
#
#   run.sh <worktree> <provider/model> <brief-file> [log-name]
#
# Writes <log>.pi.jsonl (events), <log>.pi.err (stderr) and <log>.start (launch
# epoch) beside the worktree, then prints summarize.sh's summary. <log> defaults
# to the worktree's name; pass a log name when several runs share one worktree
# (an implementation and its review, or parallel reviewers).
# Exits non-zero when pi fails or the run ends on a provider error (pi itself
# exits 0 on a 429 usage-limit error).
# Long runs: launch this in the background and wait for it to exit.
set -euo pipefail

[ $# -ge 3 ] && [ $# -le 4 ] || {
  echo "usage: run.sh <worktree> <provider/model> <brief-file> [log-name]" >&2; exit 2; }
WT=$(realpath -e "$1"); MODEL=$2; BRIEF=$3
LOG=$(dirname "$WT")/${4:-$(basename "$WT")}
[ -s "$BRIEF" ] || { echo "run.sh: brief $BRIEF is empty or missing" >&2; exit 2; }
case "$MODEL" in
  openai/gpt-6-sol) echo "run.sh: openai/gpt-6-sol is never used for delegation" >&2; exit 2 ;;
  deepseek/*) echo "run.sh: direct deepseek/* spends paid credits; use opencode-go/* unless the user asked" >&2; exit 2 ;;
esac

date +%s > "$LOG.start"
# pi-jail's /tmp is private, so the brief travels as an argument. </dev/null
# because pi -p otherwise waits on stdin forever. Streaming message_update
# events are ~99% of the output and nothing reads them, so they are dropped.
status=0
pi-jail "$WT" -p --mode json --no-session -na --model "$MODEL" "$(cat "$BRIEF")" \
  </dev/null 2>"$LOG.pi.err" \
  | jq -c --unbuffered 'select(.type != "message_update")' >"$LOG.pi.jsonl" \
  || status=$?

"$(dirname "$0")/summarize.sh" "$LOG.pi.jsonl" "$(cat "$LOG.start")"
if [ "$status" -ne 0 ]; then
  echo; echo "pi-jail exited $status; stderr tail:"; tail -20 "$LOG.pi.err"
  exit "$status"
fi
last_stop=$(jq -rs '[.[] | select(.type == "message_end" and .message.role == "assistant")
  | .message.stopReason] | last // "none"' "$LOG.pi.jsonl")
if [ "$last_stop" = error ] || [ "$last_stop" = none ]; then
  echo; echo "run.sh: run ended without a final answer (last stop: $last_stop)" >&2
  exit 3
fi
