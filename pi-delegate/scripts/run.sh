#!/usr/bin/env bash
# run.sh: run one delegated pi task inside pi-jail and log it next to the worktree.
#
#   run.sh <worktree> <provider/model> <brief-file>
#
# Writes <worktree>.pi.jsonl (events), <worktree>.pi.err (stderr) and
# <worktree>.start (launch epoch), then prints summarize.sh's summary.
# Long runs: launch this in the background and wait for it to exit.
set -euo pipefail

[ $# -eq 3 ] || { echo "usage: run.sh <worktree> <provider/model> <brief-file>" >&2; exit 2; }
WT=$(realpath -e "$1"); MODEL=$2; BRIEF=$3
[ -s "$BRIEF" ] || { echo "run.sh: brief $BRIEF is empty or missing" >&2; exit 2; }
case "$MODEL" in
  openai/gpt-6-sol) echo "run.sh: openai/gpt-6-sol is never used for delegation" >&2; exit 2 ;;
  deepseek/*) echo "run.sh: direct deepseek/* spends paid credits; use opencode-go/* unless the user asked" >&2; exit 2 ;;
esac

date +%s > "$WT.start"
# pi-jail's /tmp is private, so the brief travels as an argument. </dev/null
# because pi -p otherwise waits on stdin forever.
status=0
pi-jail "$WT" -p --mode json --no-session -na --model "$MODEL" "$(cat "$BRIEF")" \
  </dev/null >"$WT.pi.jsonl" 2>"$WT.pi.err" || status=$?

"$(dirname "$0")/summarize.sh" "$WT.pi.jsonl" "$(cat "$WT.start")"
if [ "$status" -ne 0 ]; then
  echo; echo "pi-jail exited $status; stderr tail:"; tail -20 "$WT.pi.err"
fi
exit "$status"
