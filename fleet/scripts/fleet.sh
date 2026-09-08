#!/usr/bin/env bash
# fleet: launch, track, and land isolated Pi coding agents.
#
# Each agent runs `pi -p <brief>` inside its own git worktree on its own
# branch, so an agent that writes files unattended (which is what Pi always
# does in -p mode — it has no permission system) can never touch the tree
# you are working in.
#
# State lives outside the repo, under $PI_FLEET_HOME (default ~/.pi/fleet).
#
# agy (Antigravity) is not part of this fleet. It is kept as an independent
# app for research and the frontier escape hatch — see
# docs/adr/0001-adopt-pi-as-the-fleet-harness.md.

set -uo pipefail

SELF=$(readlink -f "${BASH_SOURCE[0]}")
FLEET_HOME="${PI_FLEET_HOME:-$HOME/.pi/fleet}"
DEFAULT_TIMEOUT="${PI_FLEET_TIMEOUT:-1800}"
PREFLIGHT_TIMEOUT="${PI_FLEET_PREFLIGHT_TIMEOUT:-20}"

die() { printf 'fleet: %s\n' "$*" >&2; exit 1; }

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

# The fleet, and what each profile routes to.
#
#   name | pi --model value | probe base url | probe format
#
# All three profiles run on opencode go, the only backend wired up so far
# (see docs/adr/0002-go-shared-cap-routing.md): everything in the $60 shared
# cap. `pi-deepseek` exists because deepseek-v4-pro stays available, but it is
# not on the default path below — route to it only on an explicit request.
fleet_profiles() {
  cat <<'PROFILES'
pi-default|opencode-go/minimax-m3|https://opencode.ai/zen/go|openai
pi-plus|opencode-go/qwen3.7-plus|https://opencode.ai/zen/go|openai
pi-deepseek|opencode-go/deepseek-v4-pro|https://opencode.ai/zen/go|openai
PROFILES
}

profile_field() { fleet_profiles | awk -F'|' -v p="$1" -v n="$2" '$1==p{print $n}'; }
profile_names() { fleet_profiles | cut -d'|' -f1 | tr '\n' ' '; }

profile_model() {
  local m; m=$(profile_field "$1" 2)
  [ -n "$m" ] || die "unknown profile '$1' (known: $(profile_names))"
  printf '%s\n' "$m"
}

# --- preflight -------------------------------------------------------------

# Pi's own opencode-go key, from ~/.pi/agent/auth.json. Never let this reach a
# transcript or a log — only the probe result (the provider's reply) does.
pi_key() {
  python3 -c 'import json,sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get("opencode-go", {}).get("key", ""))
except Exception:
    print("")' "$HOME/.pi/agent/auth.json" 2>/dev/null
}

# Ask an endpoint for 24 real tokens and print what it says back. Succeeds
# quietly with a sample of the reply; fails printing the upstream's own
# error text.
#
# This has to be a completion rather than a `/v1/models` listing: a listing
# can answer 200 from an endpoint that only fails on generation, and a bare
# auth error read through a client's retry loop can burn a couple of minutes
# before the real message ever surfaces. Naming the provider's own error in
# under a second is the whole point of a preflight.
probe_endpoint() {
  # probe_endpoint <base-url> <key> <model> <openai|anthropic>
  python3 - "$1" "$2" "$3" "$4" "$PREFLIGHT_TIMEOUT" <<'PY'
import json, sys, urllib.error, urllib.request, uuid

base, key, model, fmt, timeout = sys.argv[1:6]
base = base.rstrip("/")
leaf = "/chat/completions" if fmt == "openai" else "/messages"
url = base + (leaf if base.endswith("/v1") else "/v1" + leaf)

payload = {"model": model, "max_tokens": 24,
           "messages": [{"role": "user", "content": "reply with the single word: ok"}]}
req = urllib.request.Request(
    url, data=json.dumps(payload).encode(), method="POST",
    headers={"content-type": "application/json",
             "x-api-key": key,
             "authorization": "Bearer " + key,
             "anthropic-version": "2023-06-01",
             # opencode.ai sits behind Cloudflare, which 403s the default
             # `Python-urllib/3.x` agent with `error code: 1010` — a bot-signature
             # block that looks exactly like a dead profile if you don't know it.
             # Any honest agent string is accepted.
             "user-agent": "fleet-preflight/1",
             # opencode.ai wants every request tagged with a session id for
             # its own routing/optimisation; a probe is a one-off, not part
             # of a coding session, so it gets a fresh id of its own. Pi's own
             # real runs attach this header itself.
             "x-opencode-session": str(uuid.uuid4())})


def upstream_error(body):
    """The provider's own words for what went wrong, or None if it didn't."""
    err = body.get("error")
    if not err:
        return None
    if isinstance(err, dict):
        return ": ".join(p for p in (err.get("type"), err.get("message")) if p) \
            or json.dumps(err)[:200]
    return str(err)[:200]


try:
    with urllib.request.urlopen(req, timeout=float(timeout)) as r:
        body = json.loads(r.read().decode("utf-8", "replace"))
except urllib.error.HTTPError as e:
    raw = e.read().decode("utf-8", "replace")
    try:
        detail = upstream_error(json.loads(raw))
    except ValueError:
        detail = None
    print("HTTP %d - %s" % (e.code, detail or " ".join(raw.split())[:200] or e.reason))
    sys.exit(1)
except Exception as e:
    print("%s: %s" % (type(e).__name__, e))
    sys.exit(1)

# A 200 is not proof of life: these gateways will hand back an error object
# with it.
detail = upstream_error(body)
if detail:
    print(detail)
    sys.exit(1)

if fmt == "openai":
    choices = body.get("choices") or [{}]
    text = choices[0].get("message", {}).get("content") or ""
else:
    text = "".join(b.get("text", "") for b in body.get("content", [])
                   if b.get("type") == "text")
# An empty reply is still a working profile — reasoning models routinely spend
# all 24 tokens thinking. Only an error means the profile is dead.
print(" ".join(str(text).split())[:48] or "(no text in 24 tokens, but the call succeeded)")
PY
}

# Probe a fleet profile against the real opencode-go endpoint, with Pi's own key.
probe_profile() {
  local profile=$1 model_override=${2:-} pi_model base fmt model key
  pi_model=$(profile_field "$profile" 2)
  base=$(profile_field "$profile" 3)
  fmt=$(profile_field "$profile" 4)
  model=${model_override:-${pi_model#*/}}
  key=$(pi_key)

  [ -n "$key" ] || { printf 'no opencode-go key in ~/.pi/agent/auth.json (run: pi login)\n'; return 1; }
  probe_endpoint "$base" "$key" "$model" "$fmt"
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
  local preflight="${PI_FLEET_NO_PREFLIGHT:+no}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --task|--slug)  slug=$2; shift 2 ;;
      --profile)      profile=$2; shift 2 ;;
      --model)        model=$2; shift 2 ;;
      --base)         base=$2; shift 2 ;;
      --repo)         repo=$2; shift 2 ;;
      --prompt)       prompt=$2; shift 2 ;;
      --prompt-file)  prompt_file=$2; shift 2 ;;
      --no-preflight) preflight=no; shift ;;
      *) die "launch: unknown option '$1'" ;;
    esac
  done

  [ -n "$slug" ]    || die "launch: --task <slug> is required"
  [ -n "$profile" ] || die "launch: --profile <name> is required"
  case "$slug" in *[!a-zA-Z0-9._-]*) die "launch: --task must be [a-zA-Z0-9._-] only";; esac

  command -v pi >/dev/null 2>&1 || die "launch: the pi CLI is not installed (https://pi.dev)"

  # --model overrides the profile's default. A bare model id is assumed to be
  # on opencode-go, since that's the only provider wired up so far; a value
  # containing '/' is taken as an explicit provider/model pair.
  local pi_model
  if [ -n "$model" ]; then
    case "$model" in */*) pi_model=$model ;; *) pi_model="opencode-go/$model" ;; esac
  else
    pi_model=$(profile_model "$profile") || exit 1
  fi

  # Preflight before the worktree exists, so a dead profile leaves nothing to
  # clean up. ~2s to a real error beats minutes to a wrong one.
  if [ "${preflight:-yes}" != no ]; then
    local probe
    if ! probe=$(probe_profile "$profile" "${pi_model#*/}"); then
      die "profile '$profile' is not answering — nothing was launched.
  upstream: $probe
  details:  $(basename "$SELF") verify $profile
  override: --no-preflight"
    fi
  fi

  if [ -n "$prompt_file" ]; then
    [ -f "$prompt_file" ] || die "launch: no such prompt file: $prompt_file"
    prompt=$(cat "$prompt_file")
  fi
  [ -n "$prompt" ] || die "launch: give the agent a brief via --prompt or --prompt-file"

  REPO=$(repo_root "$repo")
  local dir wt branch base_sha
  dir=$(slug_dir "$slug"); wt="$dir/worktree"; branch="pi/$slug"

  [ -e "$wt" ] && die "launch: '$slug' already exists ($wt). Use a new slug, or: fleet.sh clean $slug"
  git -C "$REPO" show-ref --verify --quiet "refs/heads/$branch" \
    && die "launch: branch '$branch' already exists. Use a new slug, or: fleet.sh clean $slug"

  base=${base:-HEAD}
  base_sha=$(git -C "$REPO" rev-parse "$base") || die "launch: cannot resolve base ref '$base'"

  mkdir -p "$dir"
  git -C "$REPO" worktree add -q -b "$branch" "$wt" "$base_sha" \
    || die "launch: git worktree add failed"

  printf '%s' "$prompt" > "$dir/brief.md"

  python3 -c 'import json,sys
json.dump(dict(zip(sys.argv[2::2], sys.argv[3::2])), open(sys.argv[1],"w"), indent=2)' \
    "$dir/meta.json" \
    slug "$slug" profile "$profile" model "$pi_model" \
    repo "$REPO" worktree "$wt" branch "$branch" base "$base" base_sha "$base_sha" \
    started "$(date -Is)"

  # Sessions live under our own fleet dir, keyed by slug, rather than under
  # Pi's default ~/.pi/agent/sessions/<cwd> — that keeps them addressable by
  # slug regardless of the worktree, and out of the way once `clean` removes
  # the worktree it was cwd'd into for this run. --name identifies the session
  # within that directory so `resume` can find it again.
  local -a argv=(pi -p "$prompt" --model "$pi_model" \
    --session-dir "$dir/sessions" --name "$slug")

  # One detached subshell owns the run and records its own exit status. Running
  # the agent and the bookkeeping in the same shell is what makes the exit code
  # reliable; a separate `wait` cannot reap a process it does not own.
  setsid bash -c 'echo $$ >"$3/pid"; cd "$1" && timeout "$2" "${@:5}" >"$3/run.log" 2>&1; rc=$?; "$4" _finish "$3" >>"$3/run.log" 2>&1; echo $rc >"$3/exit_code"' \
    _ "$wt" "$DEFAULT_TIMEOUT" "$dir" "$SELF" "${argv[@]}" </dev/null >/dev/null 2>&1 &
  disown %% 2>/dev/null

  printf 'launched %-20s profile=%s model=%s\n' "$slug" "$profile" "$pi_model"
  printf '  worktree %s\n  branch   %s (from %s)\n' "$wt" "$branch" "${base_sha:0:8}"
}

# --- status ----------------------------------------------------------------

cmd_status() {
  REPO=$(repo_root "${2:-.}")
  local root="$FLEET_HOME/$(basename "$REPO")"
  [ -d "$root" ] || { echo "no agents for $(basename "$REPO")"; return 0; }

  printf '%-22s %-10s %-12s %-26s %s\n' TASK STATE PROFILE MODEL CHANGES
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
    printf '%-22s %-10s %-12s %-26s %s\n' "$slug" "$(state_of "$d")" \
      "$(meta_get "$d" profile)" "$(meta_get "$d" model)" "$files"
  done
}

# --- verify ----------------------------------------------------------------

verify_row() { printf '%-13s %-6s %s\n' "$1" "$2" "$3"; }

# A live probe per profile, using Pi's own key. Reports the upstream's own
# words for a failure, the same way the launch preflight does.
cmd_verify() {
  local -a profiles=("$@")
  [ ${#profiles[@]} -gt 0 ] || read -r -a profiles <<< "$(profile_names)"

  local rc=0 p probe
  verify_row PROFILE RESULT DETAIL
  for p in "${profiles[@]}"; do
    if [ -z "$(profile_field "$p" 2)" ]; then
      verify_row "$p" FAIL "not a fleet profile (known: $(profile_names))"; rc=1; continue
    fi
    if probe=$(probe_profile "$p"); then
      verify_row "$p" ok "$(profile_model "$p") -> \"$probe\""
    else
      verify_row "$p" FAIL "$probe"; rc=1
    fi
  done
  return $rc
}

# --- inspect ---------------------------------------------------------------

require_slug() {
  [ -n "${1:-}" ] || die "$2: needs a task slug"
  REPO=$(repo_root .)
  DIR=$(slug_dir "$1")
  [ -f "$DIR/meta.json" ] || die "$2: no agent named '$1' (see: fleet.sh status)"
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

  local wt model; wt=$(meta_get "$DIR" worktree); model=$(meta_get "$DIR" model)
  [ "$(state_of "$DIR")" = "running" ] && die "resume: '$slug' is still running"

  # Same --session-dir/--name pair as launch, so this continues that agent's
  # own session tree with everything it already knows still loaded.
  local -a argv=(pi -p "$prompt" --model "$model" \
    --session-dir "$DIR/sessions" --name "$slug")

  rm -f "$DIR/exit_code"
  setsid bash -c 'echo $$ >"$3/pid"; cd "$1" && timeout "$2" "${@:5}" >>"$3/run.log" 2>&1; rc=$?; "$4" _finish "$3" >>"$3/run.log" 2>&1; echo $rc >"$3/exit_code"' \
    _ "$wt" "$DEFAULT_TIMEOUT" "$DIR" "$SELF" "${argv[@]}" </dev/null >/dev/null 2>&1 &
  disown %% 2>/dev/null
  printf 'resumed %s\n' "$slug"
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
  [ -n "${PI_FLEET_EXCLUDES_FILE:-}" ] && [ -f "$PI_FLEET_EXCLUDES_FILE" ] \
    && cat "$PI_FLEET_EXCLUDES_FILE"
  return 0
}

# Commit whatever the agent produced onto its own branch. Doing this the moment
# the agent finishes — rather than only at `land` — means the branch is a real
# record: `git diff main..pi/<slug>` works, and `clean` can no longer throw the
# work away with nothing left behind but a reflog entry. Pi itself never
# commits, so this is entirely the fleet's own job.
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
    printf 'skipped as build artifacts (add to .gitignore or PI_FLEET_EXCLUDES_FILE if wrong):\n'
    printf '  %s\n' $skipped; }

  git -C "$wt" -c commit.gpgsign=false commit -q -m "$(printf 'fleet(%s): %s\n\nDelegated via %s (%s).\n' \
    "$slug" "$(head -c 120 "$dir/brief.md" | tr '\n' ' ')" \
    "$(meta_get "$dir" profile)" "$(meta_get "$dir" model)")"
}

# Called by the detached runner once the agent exits. Never fails the run.
cmd_finish() {
  local dir=$1
  [ -f "$dir/meta.json" ] || return 0
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
    die "land: '$1' has no commits — the agent produced nothing to merge (check: fleet.sh log $1)"
  fi

  [ -n "$(git -C "$REPO" status --porcelain)" ] \
    && die "land: your working tree is dirty. Commit or stash first, then: fleet.sh land $1"

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
  verify) shift; cmd_verify "$@" ;;
  *) cat <<'USAGE'
fleet.sh — isolated Pi coding agents, one git worktree each

  launch --task <slug> --profile <profile> [--model <m>]
         (--prompt <text> | --prompt-file <path>) [--base <ref>] [--repo <path>]
         [--no-preflight]
         profiles: pi-default   minimax-m3        default coding reach
                   pi-plus      qwen3.7-plus       alternate model, same cap pool
                   pi-deepseek  deepseek-v4-pro    explicit request only — not a default
         --model overrides a profile's model; a bare id is assumed to be on
         opencode-go, or pass provider/model explicitly.
  status                       one line per agent: state, profile, model, files changed
  log <slug>                   raw pi output for that agent
  diff <slug>                  everything the agent changed, vs. the commit it started from
  resume <slug> --prompt <t>   another turn in the same agent's session, same worktree
  land <slug>                  commit the agent's work and merge its branch into HEAD
  clean <slug> [--force]       delete the worktree, branch, and run state
  verify [profile...]          probe every profile; report upstream errors

Auth: pi login (stores the opencode-go key in ~/.pi/agent/auth.json) — this
script does not provision it.

Env: PI_FLEET_HOME, PI_FLEET_TIMEOUT (1800s), PI_FLEET_EXCLUDES_FILE,
     PI_FLEET_PREFLIGHT_TIMEOUT (20s), PI_FLEET_NO_PREFLIGHT
USAGE
     exit 1 ;;
esac
