#!/usr/bin/env bash
# ccs-fleet: launch, track, and land isolated CCS coding agents.
#
# Each agent runs `ccs <profile> -p <brief>` inside its own git worktree on its
# own branch, so an agent that writes files unattended (which is what CCS does
# in -p mode) can never touch the tree you are working in.
#
# State lives outside the repo, under $CCS_FLEET_HOME (default ~/.ccs/fleet).

set -uo pipefail

SELF=$(readlink -f "${BASH_SOURCE[0]}")
FLEET_HOME="${CCS_FLEET_HOME:-$HOME/.ccs/fleet}"
DEFAULT_TIMEOUT="${CCS_FLEET_TIMEOUT:-1800}"

die() { printf 'ccs-fleet: %s\n' "$*" >&2; exit 1; }

# --- helpers ---------------------------------------------------------------

repo_root() {
  git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null \
    || die "not inside a git repository (cd into one, or pass --repo)"
}

slug_dir() { printf '%s/%s/%s' "$FLEET_HOME" "$(basename "$REPO")" "$1"; }

meta_get() {
  # meta_get <dir> <key>
  python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1]))[sys.argv[2]])
except Exception:
    print("")' "$1/meta.json" "$2" 2>/dev/null
}

alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }

# Which backend a profile runs on. ccs and agy are different CLIs with
# different invocation shapes (session handling, workspace trust, output
# format), so every code path that builds an argv or resumes a session has
# to branch on this.
tool_for_profile() {
  case "$1" in
    deepseek)                                           echo ccs ;;
    agy-flash|agy-pro|agy-oss|agy-sonnet|agy-opus)      echo agy ;;
    *) die "unknown profile '$1' (deepseek, agy-flash, agy-pro, agy-oss, agy-sonnet, agy-opus)" ;;
  esac
}

# agy takes a full model id rather than defaulting one per profile the way
# ccs profiles do, so each agy profile needs an explicit default. --model
# still overrides these, same as on the ccs side.
agy_default_model() {
  case "$1" in
    agy-flash)  echo gemini-3.7-flash-high ;;
    agy-pro)    echo gemini-3.1-pro-high ;;
    agy-oss)    echo gpt-oss-120b-medium ;;
    agy-sonnet) echo claude-sonnet-4-6 ;;
    agy-opus)   echo claude-opus-4-6-thinking ;;
  esac
}

state_of() {
  # state_of <dir> -> running | done | failed(N) | timeout | died
  # The runner writes its own pid on start and its exit code on finish, so
  # state is read off the filesystem rather than from a shell job table that
  # disappears the moment the launching command returns.
  local d=$1 ec=""
  [ -f "$d/exit_code" ] && ec=$(cat "$d/exit_code")
  if [ -n "$ec" ]; then
    case "$ec" in
      0)   echo done ;;
      124) echo timeout ;;
      *)   echo "failed($ec)" ;;
    esac
  elif alive "$(cat "$d/pid" 2>/dev/null)"; then
    echo running
  else
    echo died
  fi
}

# --- launch ----------------------------------------------------------------

cmd_launch() {
  local slug="" profile="" model="" base="" repo="." prompt="" prompt_file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --task|--slug)  slug=$2; shift 2 ;;
      --profile)      profile=$2; shift 2 ;;
      --model)        model=$2; shift 2 ;;
      --base)         base=$2; shift 2 ;;
      --repo)         repo=$2; shift 2 ;;
      --prompt)       prompt=$2; shift 2 ;;
      --prompt-file)  prompt_file=$2; shift 2 ;;
      *) die "launch: unknown option '$1'" ;;
    esac
  done

  [ -n "$slug" ]    || die "launch: --task <slug> is required"
  [ -n "$profile" ] || die "launch: --profile <name> is required"
  case "$slug" in *[!a-zA-Z0-9._-]*) die "launch: --task must be [a-zA-Z0-9._-] only";; esac

  local tool; tool=$(tool_for_profile "$profile") || exit 1
  [ "$tool" = agy ] && model=${model:-$(agy_default_model "$profile")}

  if [ -n "$prompt_file" ]; then
    [ -f "$prompt_file" ] || die "launch: no such prompt file: $prompt_file"
    prompt=$(cat "$prompt_file")
  fi
  [ -n "$prompt" ] || die "launch: give the agent a brief via --prompt or --prompt-file"

  REPO=$(repo_root "$repo")
  local dir wt branch base_sha sid
  dir=$(slug_dir "$slug"); wt="$dir/worktree"; branch="ccs/$slug"

  [ -e "$wt" ] && die "launch: '$slug' already exists ($wt). Use a new slug, or: ccs-fleet.sh clean $slug"
  git -C "$REPO" show-ref --verify --quiet "refs/heads/$branch" \
    && die "launch: branch '$branch' already exists. Use a new slug, or: ccs-fleet.sh clean $slug"

  base=${base:-HEAD}
  base_sha=$(git -C "$REPO" rev-parse "$base") || die "launch: cannot resolve base ref '$base'"

  mkdir -p "$dir"
  git -C "$REPO" worktree add -q -b "$branch" "$wt" "$base_sha" \
    || die "launch: git worktree add failed"

  # ccs takes a session id up front; agy hands one back in its JSON response
  # once the run finishes (captured as conversation_id below), so sid starts
  # empty on the agy path and cmd_finish fills it in.
  sid=""
  [ "$tool" = ccs ] && sid=$(cat /proc/sys/kernel/random/uuid)
  printf '%s' "$prompt" > "$dir/brief.md"

  python3 -c 'import json,sys
json.dump(dict(zip(sys.argv[2::2], sys.argv[3::2])), open(sys.argv[1],"w"), indent=2)' \
    "$dir/meta.json" \
    slug "$slug" profile "$profile" tool "$tool" model "$model" session_id "$sid" \
    repo "$REPO" worktree "$wt" branch "$branch" base "$base" base_sha "$base_sha" \
    started "$(date -Is)"

  local -a argv=()
  if [ "$tool" = ccs ]; then
    # --model is a claude passthrough arg: it really does change the model,
    # even though CCS's summary table keeps printing the profile default.
    # --session-id is what makes parallel agents resumable; ~/.ccs/
    # delegation-sessions.json only remembers <profile>:latest and would
    # otherwise be clobbered by whichever sibling agent finished last.
    argv=(ccs "$profile")
    [ -n "$model" ] && argv+=(--model "$model")
    argv+=(--session-id "$sid" -p "$prompt")
  else
    # agy only trusts workspaces listed in its own settings.json; anywhere
    # else (every worktree, by construction) it silently redirects writes to
    # its scratch directory instead of erroring. --add-dir is what grants
    # trust for this run, so it is not optional the way it would be for ccs.
    argv=(agy --model "$model" --dangerously-skip-permissions \
      --add-dir "$wt" --output-format json -p "$prompt")
  fi

  # One detached subshell owns the run and records its own exit status. Running
  # the agent and the bookkeeping in the same shell is what makes the exit code
  # reliable; a separate `wait` cannot reap a process it does not own.
  setsid bash -c 'echo $$ >"$3/pid"; cd "$1" && timeout "$2" "${@:5}" >"$3/run.log" 2>&1; rc=$?; "$4" _finish "$3" >>"$3/run.log" 2>&1; echo $rc >"$3/exit_code"' \
    _ "$wt" "$DEFAULT_TIMEOUT" "$dir" "$SELF" "${argv[@]}" </dev/null >/dev/null 2>&1 &
  disown %% 2>/dev/null

  printf 'launched %-20s profile=%s tool=%s%s\n' "$slug" "$profile" "$tool" \
    "${model:+ model=$model}"
  printf '  worktree %s\n  branch   %s (from %s)\n' "$wt" "$branch" "${base_sha:0:8}"
}

# --- status ----------------------------------------------------------------

cmd_status() {
  REPO=$(repo_root "${2:-.}")
  local root="$FLEET_HOME/$(basename "$REPO")"
  [ -d "$root" ] || { echo "no agents for $(basename "$REPO")"; return 0; }

  printf '%-22s %-10s %-4s %-12s %-24s %s\n' TASK STATE TOOL PROFILE MODEL CHANGES
  local d slug wt files
  for d in "$root"/*/; do
    [ -f "$d/meta.json" ] || continue
    slug=$(meta_get "$d" slug); wt=$(meta_get "$d" worktree)
    files="-"
    if [ -d "$wt" ]; then
      # Everything the agent changed since it started, committed or not — the
      # runner commits on completion, so counting only uncommitted files would
      # report a successful agent as having done nothing.
      git -C "$wt" add -A -N >/dev/null 2>&1
      files=$(git -C "$wt" diff --name-only "$(meta_get "$d" base_sha)" 2>/dev/null | wc -l)
      files="$files file(s)"
    fi
    printf '%-22s %-10s %-4s %-12s %-24s %s\n' "$slug" "$(state_of "$d")" \
      "$(meta_get "$d" tool)" "$(meta_get "$d" profile)" "$(meta_get "$d" model)" "$files"
  done
}

# --- inspect ---------------------------------------------------------------

require_slug() {
  [ -n "${1:-}" ] || die "$2: needs a task slug"
  REPO=$(repo_root .)
  DIR=$(slug_dir "$1")
  [ -f "$DIR/meta.json" ] || die "$2: no agent named '$1' (see: ccs-fleet.sh status)"
}

cmd_log()  { require_slug "${1:-}" log;  cat "$DIR/run.log" 2>/dev/null || echo "(no output yet)"; }

cmd_diff() {
  require_slug "${1:-}" diff
  local wt; wt=$(meta_get "$DIR" worktree)
  [ -d "$wt" ] || die "diff: worktree is gone: $wt"
  # Everything the agent did, committed or not, against the commit it started from.
  git -C "$wt" add -A -N >/dev/null 2>&1
  git -C "$wt" --no-pager diff "$(meta_get "$DIR" base_sha)"
}

cmd_resume() {
  local slug=${1:-}; shift || true
  local prompt=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --prompt)      prompt=$2; shift 2 ;;
      --prompt-file) prompt=$(cat "$2"); shift 2 ;;
      *) die "resume: unknown option '$1'" ;;
    esac
  done
  require_slug "$slug" resume
  [ -n "$prompt" ] || die "resume: --prompt or --prompt-file is required"

  local wt sid profile model tool; wt=$(meta_get "$DIR" worktree)
  sid=$(meta_get "$DIR" session_id); profile=$(meta_get "$DIR" profile); model=$(meta_get "$DIR" model)
  tool=$(meta_get "$DIR" tool); [ -n "$tool" ] || tool=ccs   # older runs predate the tool field
  [ "$(state_of "$DIR")" = "running" ] && die "resume: '$slug' is still running"

  local -a argv=()
  if [ "$tool" = ccs ]; then
    argv=(ccs "$profile")
    [ -n "$model" ] && argv+=(--model "$model")
    argv+=(--resume "$sid" -p "$prompt")
  else
    [ -n "$sid" ] || die "resume: no conversation id recorded for '$slug' yet — check: ccs-fleet.sh log $slug"
    argv=(agy --model "$model" --dangerously-skip-permissions \
      --add-dir "$wt" --conversation "$sid" --output-format json -p "$prompt")
  fi

  rm -f "$DIR/exit_code"
  setsid bash -c 'echo $$ >"$3/pid"; cd "$1" && timeout "$2" "${@:5}" >>"$3/run.log" 2>&1; rc=$?; "$4" _finish "$3" >>"$3/run.log" 2>&1; echo $rc >"$3/exit_code"' \
    _ "$wt" "$DEFAULT_TIMEOUT" "$DIR" "$SELF" "${argv[@]}" </dev/null >/dev/null 2>&1 &
  disown %% 2>/dev/null
  printf 'resumed %s (session %s)\n' "$slug" "${sid:0:8}"
}

# --- land / clean ----------------------------------------------------------

# Ephemeral build/test artifacts that an agent (or your own verification run)
# leaves lying around. A repo without a .gitignore has no defence against these,
# and `git add -A` would otherwise sweep them into the commit. Anything skipped
# is always reported, so an exclusion can never quietly swallow real work.
fleet_excludes() {
  cat <<'PATTERNS'
__pycache__/
*.py[cod]
*.so
.pytest_cache/
.mypy_cache/
.ruff_cache/
.tox/
.coverage
.coverage.*
htmlcov/
*.egg-info/
.DS_Store
node_modules/
.venv/
PATTERNS
  [ -n "${CCS_FLEET_EXCLUDES_FILE:-}" ] && [ -f "$CCS_FLEET_EXCLUDES_FILE" ] \
    && cat "$CCS_FLEET_EXCLUDES_FILE"
  return 0
}

# Commit whatever the agent produced onto its own branch. Doing this the moment
# the agent finishes — rather than only at `land` — means the branch is a real
# record: `git diff main..ccs/<slug>` works, and `clean` can no longer throw the
# work away with nothing left behind but a reflog entry.
stage_and_commit() {
  local dir=$1 wt=$2 slug=$3
  [ -d "$wt" ] || return 1
  [ -n "$(git -C "$wt" status --porcelain)" ] || return 1

  local exclude_file skipped
  exclude_file=$(mktemp); fleet_excludes > "$exclude_file"
  skipped=$(comm -23 \
    <(git -C "$wt" ls-files --others --exclude-standard | sort) \
    <(git -C "$wt" -c core.excludesFile="$exclude_file" \
        ls-files --others --exclude-standard | sort))
  git -C "$wt" -c core.excludesFile="$exclude_file" add -A
  rm -f "$exclude_file"

  if [ -z "$(git -C "$wt" diff --cached --name-only)" ]; then
    printf 'nothing to commit for %s (only ephemeral artifacts)\n' "$slug"
    [ -n "$skipped" ] && printf '  skipped: %s\n' $skipped
    return 1
  fi

  printf 'committing %s:\n' "$slug"
  git -C "$wt" diff --cached --name-status | sed 's/^/  /'
  [ -n "$skipped" ] && {
    printf 'skipped as build artifacts (add to .gitignore or CCS_FLEET_EXCLUDES_FILE if wrong):\n'
    printf '  %s\n' $skipped; }

  git -C "$wt" -c commit.gpgsign=false commit -q -m "$(printf 'ccs-fleet(%s): %s\n\nDelegated via %s profile %s.\n' \
    "$slug" "$(head -c 120 "$dir/brief.md" | tr '\n' ' ')" \
    "$(meta_get "$dir" tool)" "$(meta_get "$dir" profile)")"
}

# agy hands back its conversation_id in the JSON blob on stdout rather than
# accepting a caller-chosen id up front the way --session-id does for ccs, so
# the id has to be pulled out of run.log after the fact. Scans from the end
# and takes the last line that parses as JSON, in case anything else ever
# lands in the log ahead of it.
agy_conversation_id() {
  python3 -c 'import json,sys
for line in reversed(open(sys.argv[1]).read().splitlines()):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    print(d.get("conversation_id", ""))
    break' "$1" 2>/dev/null
}

# Called by the detached runner once the agent exits. Never fails the run.
cmd_finish() {
  local dir=$1
  [ -f "$dir/meta.json" ] || return 0

  if [ "$(meta_get "$dir" tool)" = agy ] && [ -z "$(meta_get "$dir" session_id)" ]; then
    local cid; cid=$(agy_conversation_id "$dir/run.log")
    if [ -n "$cid" ]; then
      python3 -c 'import json,sys
d = json.load(open(sys.argv[1]))
d["session_id"] = sys.argv[2]
json.dump(d, open(sys.argv[1], "w"), indent=2)' "$dir/meta.json" "$cid"
    fi
  fi

  stage_and_commit "$dir" "$(meta_get "$dir" worktree)" "$(meta_get "$dir" slug)" || true
  return 0
}

cmd_land() {
  require_slug "${1:-}" land
  local wt branch; wt=$(meta_get "$DIR" worktree); branch=$(meta_get "$DIR" branch)
  [ "$(state_of "$DIR")" = "running" ] && die "land: '$1' is still running"

  # The runner already committed when the agent finished; this catches anything
  # touched since (a manual tweak, or a resume that has not committed yet).
  stage_and_commit "$DIR" "$wt" "$1" || true

  if [ -z "$(git -C "$REPO" log --oneline "$(meta_get "$DIR" base_sha)".."$branch" 2>/dev/null)" ]; then
    die "land: '$1' has no commits — the agent produced nothing to merge (check: ccs-fleet.sh log $1)"
  fi

  [ -n "$(git -C "$REPO" status --porcelain)" ] \
    && die "land: your working tree is dirty. Commit or stash first, then: ccs-fleet.sh land $1"

  git -C "$REPO" merge --no-ff "$branch" \
    || die "land: merge hit conflicts. Resolve in $REPO, then commit."
  printf 'landed %s -> %s\n' "$branch" "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
}

cmd_clean() {
  local slug=${1:-} force=${2:-}
  require_slug "$slug" clean
  local wt branch; wt=$(meta_get "$DIR" worktree); branch=$(meta_get "$DIR" branch)
  [ "$(state_of "$DIR")" = "running" ] && [ "$force" != "--force" ] \
    && die "clean: '$slug' is still running (use --force to discard it anyway)"
  git -C "$REPO" worktree remove --force "$wt" 2>/dev/null
  git -C "$REPO" branch -D "$branch" 2>/dev/null
  rm -rf "$DIR"
  printf 'cleaned %s\n' "$slug"
}

# --- dispatch --------------------------------------------------------------

case "${1:-}" in
  launch) shift; cmd_launch "$@" ;;
  status) shift; cmd_status "$@" ;;
  log)    shift; cmd_log "$@" ;;
  diff)   shift; cmd_diff "$@" ;;
  resume) shift; cmd_resume "$@" ;;
  _finish) shift; cmd_finish "$@" ;;
  land)   shift; cmd_land "$@" ;;
  clean)  shift; cmd_clean "$@" ;;
  *) cat <<'USAGE'
ccs-fleet.sh — isolated CCS/agy coding agents, one git worktree each

  launch --task <slug> --profile <profile> [--model <m>]
         (--prompt <text> | --prompt-file <path>) [--base <ref>] [--repo <path>]
         profiles: deepseek                    (CCS, local)
                   agy-flash, agy-pro, agy-oss,  (Antigravity/Gemini + GPT-OSS +
                   agy-sonnet, agy-opus           Claude via Google, remote & billed)
  status                       one line per agent: state, tool, profile, files changed
  log <slug>                   raw CCS/agy output for that agent
  diff <slug>                  everything the agent changed, vs. the commit it started from
  resume <slug> --prompt <t>   another turn in the same agent's session, same worktree
  land <slug>                  commit the agent's work and merge its branch into HEAD
  clean <slug> [--force]       delete the worktree, branch, and run state
USAGE
     exit 1 ;;
esac
