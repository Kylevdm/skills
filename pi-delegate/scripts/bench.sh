#!/usr/bin/env bash
# bench.sh: report on the delegation benchmark (see record.sh).
#
#   bench.sh [--since YYYY-MM-DD] [--role implement|review|...]   per model, task type and size
#   bench.sh --matrix [--no-baseline]                             score per size x risk, best models first
#   bench.sh --window                                             Go allowance used, last 5 h and 7 days
#   bench.sh --export-baseline                                    rewrite assets/baseline.tsv from local runs
#   bench.sh --groups                                             runs on the same diff and brief, side by side
#
# Scores (0-1):
# - Implementation runs score by outcome (merged 1, fixed-small 0.7, rerun 0.3,
#   rejected 0), less 0.05 per defect and 0.25 per severe defect found in the
#   delivered diff by anyone, floored at 0; 0 whenever safety_relaxed=true.
# - Reviews score 0.4 x precision (real / reported) + 0.6 x recall, where recall
#   counts a severe finding twice: (real + severe) / (real + severe + missed +
#   missed_severe). Without findings_missed a review scores on precision alone.
# - A run is unscored when it ended on a provider error or its cause is not the
#   model (cause=provider|brief|setup): a usage limit, a gap in the brief or a
#   setup mistake says nothing about the model's work.
# --matrix ranks by a shrunk mean: each cell also holds PRIOR_RUNS phantom runs at
# PRIOR_SCORE, so one lucky run can't outrank a steady record. It also blends in
# the public baseline in assets/baseline.tsv: a baseline cell weighs as up to 3
# runs, one less for each local run in that cell, so a new install starts from
# the maintainer's numbers and its own runs take over.
# Counts only runs recorded through run.sh / record.sh; Go spend from interactive
# pi sessions or other tools is invisible here, so leave headroom.
set -euo pipefail

RUNS=${PI_DELEGATE_RUNS:-$HOME/.local/share/pi-delegate/runs.jsonl}
BASELINE=$(dirname "$0")/../assets/baseline.tsv
[ -s "$RUNS" ] || [ "${1:-}" = --matrix ] || { echo "bench.sh: no records yet in $RUNS" >&2; exit 1; }

python3 -I - "$RUNS" "$BASELINE" "$@" <<'PY'
import json, os, statistics, sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

path, baseline_path, args = sys.argv[1], sys.argv[2], sys.argv[3:]
runs = [json.loads(line) for line in open(path) if line.strip()] if os.path.exists(path) else []
for r in runs:
    r["_start"] = datetime.fromisoformat(r["started"].replace("Z", "+00:00"))

OUTCOME_SCORE = {"merged": 1.0, "fixed-small": 0.7, "rerun": 0.3, "rejected": 0.0}
BASELINE_WEIGHT = 3
PRIOR_RUNS, PRIOR_SCORE = 2, 0.7
MIN_PUBLIC_RUNS = 7
SIZES, RISKS = ("S", "M", "L"), ("low", "medium", "high")
NOT_MODEL = {"provider", "brief", "setup"}

def kind(r):
    return "review" if r.get("role", "implement").endswith("review") else "implement"

def excused(r):
    return bool(r.get("error")) or r.get("cause") in NOT_MODEL

def score(r):
    if excused(r):
        return None
    if kind(r) == "review":
        real, total = r.get("findings_real"), r.get("findings_total")
        if real is None or total is None:
            return None
        missed = r.get("findings_missed")
        if missed is None:
            return real / total if total else None
        found = real + r.get("findings_severe", 0)
        lost = missed + r.get("missed_severe", 0)
        recall = found / (found + lost) if found + lost else 1.0
        return 0.4 * (real / total if total else 1.0) + 0.6 * recall
    if r.get("safety_relaxed") is True:
        return 0.0
    base = OUTCOME_SCORE.get(r.get("outcome"))
    if base is None:
        return None
    severe = r.get("defects_severe", 0)
    minor = max(0, r.get("defects", 0) - severe)
    return max(0.0, base - 0.05 * minor - 0.25 * severe)

def med(values):
    values = [v for v in values if v is not None]
    return statistics.median(values) if values else None

def fmt(value, spec, scale=1, suffix=""):
    return "-" if value is None else f"{value * scale:{spec}}{suffix}"

def mean_score(rs):
    values = [v for v in map(score, rs) if v is not None]
    return statistics.mean(values) if values else None

def cells(rs):
    """(kind, size, risk, model) -> scored runs, for the matrix and the baseline."""
    out = defaultdict(list)
    for r in rs:
        if score(r) is not None:
            out[(kind(r), r.get("size", "-"), r.get("risk", "-"), f'{r["provider"]}/{r["model"]}')].append(r)
    return out

if args[:1] == ["--export-baseline"]:
    with open(baseline_path, "w") as f:
        f.write("# pi-delegate baseline scores, aggregated from the maintainer's local benchmark\n"
                f"# ({datetime.now(timezone.utc):%Y-%m-%d}; bench.sh --export-baseline). No repos, issues or code.\n"
                f"# Only cells with {MIN_PUBLIC_RUNS}+ runs are published. score: 0-1, see bench.sh. allowance: median share of the OpenCode Go month (- for Plus).\n"
                "# kind\tsize\trisk\tmodel\truns\tscore\tallowance\tminutes\n")
        for (k, size, risk, model), rs in sorted(cells(runs).items()):
            if len(rs) < MIN_PUBLIC_RUNS or (k == "implement" and "-" in (size, risk)):
                continue
            f.write("\t".join((k, size, risk, model, str(len(rs)),
                               f"{mean_score(rs):.2f}",
                               fmt(med([r["allowance"] for r in rs]), ".4f"),
                               fmt(med([r["wall_s"] for r in rs]), ".0f", 1 / 60))) + "\n")
    print(f"wrote {os.path.normpath(baseline_path)}; review the diff before committing it")
    sys.exit(0)

if args[:1] == ["--matrix"]:
    base = {}
    if "--no-baseline" not in args and os.path.exists(baseline_path):
        for line in open(baseline_path):
            if line.strip() and not line.startswith("#"):
                k, size, risk, model, n, sc, allow, _ = line.rstrip("\n").split("\t")
                base[(k, size, risk, model)] = (int(n), float(sc),
                                                None if allow == "-" else float(allow))
    local = cells(runs)
    def entry(key):
        rs = local.get(key, [])
        n, sc, allow = base.get(key, (0, 0.0, None))
        w = max(0, min(n, BASELINE_WEIGHT) - len(rs))
        blended = ((w * sc + sum(score(r) for r in rs) + PRIOR_RUNS * PRIOR_SCORE)
                   / (w + len(rs) + PRIOR_RUNS))
        allow = med([r["allowance"] for r in rs]) if rs else allow
        cost = "Plus" if key[3].startswith("openai/") else fmt(allow, ".1f", 100, "%")
        raw = f"raw {mean_score(rs):.2f}, " if rs else ""
        return blended, f"{key[3]} {blended:.2f} ({raw}n {len(rs)}{f' +{w} base' if w else ''}, {cost})"
    for k, rows in (("implement", [(s, r) for s in SIZES for r in RISKS]), ("review", None)):
        keys = set(local) | set(base)
        if rows is None:
            rows = sorted({(key[1], key[2]) for key in keys if key[0] == k})
        print(f"{k} score by size/risk, best first (shrunk score; raw mean, n local runs +baseline weight, median Go allowance)")
        for size, risk in rows:
            found = sorted((entry(key) for key in keys if key[:3] == (k, size, risk)), reverse=True)
            print(f"  {size}/{risk:7} " + ("   ".join(text for _, text in found[:3]) or "no data"))
        print()
    unrisked = sum(1 for r in runs if kind(r) == "implement" and score(r) is not None and "risk" not in r)
    if unrisked:
        print(f"{unrisked} scored implement run(s) have no risk and sit outside the matrix: record.sh set <id> risk=...")
    sys.exit(0)

if args[:1] == ["--groups"]:
    groups = defaultdict(list)
    for r in runs:
        if r.get("group"):
            groups[r["group"]].append(r)
    for g, rs in sorted(groups.items(), key=lambda kv: kv[1][0]["_start"]):
        print(f'{g}  ({rs[0]["_start"]:%Y-%m-%d})')
        for r in sorted(rs, key=lambda r: -(score(r) or 0)):
            if kind(r) == "review":
                detail = (f'real {r.get("findings_real", "-")}/{r.get("findings_total", "-")}'
                          f'  severe {r.get("findings_severe", "-")}'
                          f'  missed {r.get("findings_missed", "-")}/{r.get("missed_severe", "-")}')
            else:
                detail = (f'{r.get("outcome", "-")}  defects {r.get("defects", "-")}'
                          f'/{r.get("defects_severe", "-")} severe')
            print(f'  {r["provider"]}/{r["model"]:28} {kind(r):9} {fmt(score(r), ".2f"):5} {detail}')
    if not groups:
        print("no grouped runs yet: record.sh set <id> group=<label> on runs over the same diff and brief")
    sys.exit(0)

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

groups = defaultdict(list)
for r in runs:
    groups[(f'{r["provider"]}/{r["model"]}', r.get("task", "?"), r.get("size", "?"))].append(r)

header = ("model", "task", "size", "runs", "merged", "fixed", "rerun", "reject", "relaxed",
          "findings", "excused", "score", "med $", "med allow", "med min")
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
                 str(sum(1 for r in rs if excused(r))),
                 fmt(mean_score(rs), ".2f"),
                 fmt(med([r["cost_usd"] for r in rs]), ".2f"),
                 fmt(med([r["allowance"] for r in rs]), ".1f", 100, "%"),
                 fmt(med([r["wall_s"] for r in rs]), ".0f", 1 / 60)))
widths = [max(len(row[i]) for row in rows) for i in range(len(header))]
for row in rows:
    print("  ".join(cell.ljust(w) for cell, w in zip(row, widths)).rstrip())

unlabelled = sum(1 for r in runs if "outcome" not in r and kind(r) != "review")
if unlabelled:
    print(f"\n{unlabelled} run(s) have no outcome yet: record.sh set <id> outcome=...")
uncaused = sum(1 for r in runs if r.get("outcome") in ("rerun", "rejected") and "cause" not in r and not r.get("error"))
if uncaused:
    print(f"\n{uncaused} rerun/rejected run(s) have no cause and score against the model: record.sh set <id> cause=...")

errors = [r for r in runs if r.get("error")]
if errors:
    print("\nerrors (model, kind, UTC hour started):")
    for r in errors:
        print(f'  {r["provider"]}/{r["model"]}  {r["error"]}  {r["_start"]:%a %H}:00  {r["id"]}')
PY
