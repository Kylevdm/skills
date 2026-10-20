#!/usr/bin/env bash
# bench.sh: report on the delegation benchmark (see record.sh).
#
#   bench.sh [--since YYYY-MM-DD] [--role implement|review|...]   per model, task type and size
#   bench.sh --window                                             Go allowance used, last 5 h and 7 days
#
# Counts only runs recorded through run.sh / record.sh; Go spend from interactive
# pi sessions or other tools is invisible here, so leave headroom.
set -euo pipefail

RUNS=${PI_DELEGATE_RUNS:-$HOME/.local/share/pi-delegate/runs.jsonl}
[ -s "$RUNS" ] || { echo "bench.sh: no records yet in $RUNS" >&2; exit 1; }

python3 -I - "$RUNS" "$@" <<'PY'
import json, statistics, sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

path, args = sys.argv[1], sys.argv[2:]
runs = [json.loads(line) for line in open(path) if line.strip()]
for r in runs:
    r["_start"] = datetime.fromisoformat(r["started"].replace("Z", "+00:00"))

if args[:1] == ["--window"]:
    now = datetime.now(timezone.utc)
    for label, span, cap in (("last 5 h", timedelta(hours=5), 20), ("last 7 days", timedelta(days=7), 50)):
        used = sum(r["allowance"] or 0 for r in runs
                   if r["_start"] + timedelta(seconds=r.get("wall_s") or 0) >= now - span)
        print(f"{label:12} {used * 100:5.1f}% of the Go allowance used (window cap {cap}%)")
    unknown = sorted({r["model"] for r in runs if r["provider"] == "opencode-go" and r["allowance"] is None})
    if unknown:
        print("limit unknown for: " + ", ".join(unknown) + " (not counted; refresh go-limits.tsv)")
    sys.exit(0)

since = role = None
while args:
    flag, value, args = args[0], args[1], args[2:]
    if flag == "--since":
        since = datetime.fromisoformat(value).replace(tzinfo=timezone.utc)
    elif flag == "--role":
        role = value
    else:
        sys.exit(f"bench.sh: unknown option {flag}")
runs = [r for r in runs if (since is None or r["_start"] >= since) and (role is None or r.get("role") == role)]

def med(values):
    values = [v for v in values if v is not None]
    return statistics.median(values) if values else None

def fmt(value, spec, scale=1, suffix=""):
    return "-" if value is None else f"{value * scale:{spec}}{suffix}"

groups = defaultdict(list)
for r in runs:
    groups[(f'{r["provider"]}/{r["model"]}', r.get("task", "?"), r.get("size", "?"))].append(r)

header = ("model", "task", "size", "runs", "merged", "fixed", "rerun", "reject", "relaxed",
          "findings", "med $", "med allow", "med min")
rows = [header]
for (model, task, size), rs in sorted(groups.items()):
    outcomes = [r.get("outcome") for r in rs]
    judged = [r for r in rs if r.get("findings_real") is not None and r.get("findings_total") is not None]
    real = sum(r["findings_real"] for r in judged)
    total = sum(r["findings_total"] for r in judged)
    rows.append((model, task, size, str(len(rs)),
                 str(outcomes.count("merged")), str(outcomes.count("fixed-small")),
                 str(outcomes.count("rerun")), str(outcomes.count("rejected")),
                 str(sum(1 for r in rs if r.get("safety_relaxed") is True)),
                 f"{real}/{total}" if total else "-",
                 fmt(med([r["cost_usd"] for r in rs]), ".2f"),
                 fmt(med([r["allowance"] for r in rs]), ".1f", 100, "%"),
                 fmt(med([r["wall_s"] for r in rs]), ".0f", 1 / 60)))
widths = [max(len(row[i]) for row in rows) for i in range(len(header))]
for row in rows:
    print("  ".join(cell.ljust(w) for cell, w in zip(row, widths)).rstrip())

unlabelled = sum(1 for r in runs if "outcome" not in r and r.get("role", "implement") != "review")
if unlabelled:
    print(f"\n{unlabelled} run(s) have no outcome yet: record.sh set <id> outcome=...")

errors = [r for r in runs if r.get("error")]
if errors:
    print("\nerrors (model, kind, UTC hour started):")
    for r in errors:
        print(f'  {r["provider"]}/{r["model"]}  {r["error"]}  {r["_start"]:%a %H}:00  {r["id"]}')
PY
