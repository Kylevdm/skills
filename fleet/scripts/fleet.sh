#!/usr/bin/env bash
# fleet: launch, track, and land isolated CCS/agy coding agents.
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
PREFLIGHT_TIMEOUT="${CCS_FLEET_PREFLIGHT_TIMEOUT:-20}"

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

# The fleet, and what each profile is supposed to be pointed at.
#
#   name | tool | base url | model | transport
#
# For ccs profiles the last three columns are what `verify` compares the live
# `~/.ccs/<name>.settings.json` against, so a profile that drifts back to the
# unfunded PAYG endpoint, or picks up a `[1m]` suffix that opencode's
# subscription rejects, is caught by a command instead of by a hung agent.
# For agy profiles only the model column is meaningful — agy takes a full
# model id per invocation rather than reading a profile file.
#
# `transport` is the value of CCS_DROID_PROVIDER, and it is load-bearing
# rather than cosmetic: ccs routes any profile resolving to an
# OpenAI-compatible provider through its own local Anthropic->OpenAI proxy
# daemon, and sends the rest straight at the upstream's `/v1/messages`.
# `anthropic` here means "go direct"; `generic-chat-completion-api` means
# "ccs will start and own a proxy for this one".
fleet_profiles() {
  cat <<'PROFILES'
oc-fast|ccs|https://opencode.ai/zen/go|deepseek-v4-flash|anthropic
oc-smart|ccs|https://opencode.ai/zen/go|deepseek-v4-pro|anthropic
oc-free|ccs|https://opencode.ai/zen|hy3-free|generic-chat-completion-api
deepseek|ccs|https://api.deepseek.com/anthropic|deepseek-v4-pro[1m]|anthropic
agy-gemini|agy|-|gemini-3.1-pro-high|-
agy-opus|agy|-|claude-opus-4-6-thinking|-
PROFILES
}

profile_field() { fleet_profiles | awk -F'|' -v p="$1" -v n="$2" '$1==p{print $n}'; }
profile_names() { fleet_profiles | cut -d'|' -f1 | tr '\n' ' '; }

# Which backend a profile runs on. ccs and agy are different CLIs with
# different invocation shapes (session handling, workspace trust, output
# format), so every code path that builds an argv or resumes a session has
# to branch on this.
tool_for_profile() {
  local t; t=$(profile_field "$1" 2)
  [ -n "$t" ] || die "unknown profile '$1' (known: $(profile_names))"
  printf '%s\n' "$t"
}

# agy takes a full model id rather than defaulting one per profile the way
# ccs profiles do, so each agy profile needs an explicit default. --model
# still overrides these, same as on the ccs side.
agy_default_model() { profile_field "$1" 4; }

# --- preflight -------------------------------------------------------------

# One value out of a ccs profile's settings file, never the whole file:
# ~/.ccs/*.settings.json hold live API tokens in plaintext and must not reach
# a transcript or a log.
ccs_setting() {
  python3 -c 'import json,sys
try:
    env = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
env = env.get("env", env)
print(env.get(sys.argv[2], ""))' "$HOME/.ccs/$1.settings.json" "$2" 2>/dev/null
}

# Ask an endpoint for 24 real tokens and print what it says back. Succeeds
# quietly with a sample of the reply; fails printing the upstream's own
# error text.
#
# This has to be a completion rather than a `/v1/models` listing. The outage
# this exists to catch — every profile pointed at opencode's unfunded PAYG
# endpoint instead of the subscription path — answered `/v1/models` with a
# clean 200 and only failed on generation, with a 401 that Claude Code's SDK
# read as `authentication_failed` and retried ten times behind exponential
# backoff. That cost 118 seconds and destroyed the real message on the way.
# `CreditsError: Insufficient balance` and `RegionError: requires explicit
# opt in` each name their own fix; surfacing them is the whole job here.
probe_endpoint() {
  # probe_endpoint <base-url> <key> <model> <anthropic|openai>
  python3 - "$1" "$2" "$3" "$4" "$PREFLIGHT_TIMEOUT" <<'PY'
import json, sys, urllib.error, urllib.request

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
             "user-agent": "fleet-preflight/1"})


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

# Probe a ccs profile the way ccs itself will actually reach it.
probe_ccs_profile() {
  local profile=$1 model=${2:-} base key transport fmt
  base=$(ccs_setting "$profile" ANTHROPIC_BASE_URL)
  key=$(ccs_setting "$profile" ANTHROPIC_AUTH_TOKEN)
  [ -n "$key" ] || key=$(ccs_setting "$profile" ANTHROPIC_API_KEY)
  transport=$(ccs_setting "$profile" CCS_DROID_PROVIDER)
  [ -n "$model" ] || model=$(ccs_setting "$profile" ANTHROPIC_MODEL)

  [ -n "$base" ] || { printf 'no ANTHROPIC_BASE_URL in ~/.ccs/%s.settings.json (registered? try: ccs api list)\n' "$profile"; return 1; }
  [ -n "$key" ]  || { printf 'no API key in ~/.ccs/%s.settings.json\n' "$profile"; return 1; }
  [ -n "$model" ] || { printf 'no ANTHROPIC_MODEL in ~/.ccs/%s.settings.json\n' "$profile"; return 1; }

  # ccs hands an OpenAI-compatible profile to its own local proxy, which calls
  # `/chat/completions` upstream. Probing `/v1/messages` for those would report
  # a failure the real run never hits, so follow the same rule ccs does.
  case "$transport" in
    generic-chat-completion-api|openai) fmt=openai ;;
    *)                                  fmt=anthropic ;;
  esac
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
  local preflight="${CCS_FLEET_NO_PREFLIGHT:+no}"
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

  local tool; tool=$(tool_for_profile "$profile") || exit 1

  # agy is optional. Without it the agy-* profiles are simply unavailable, and
  # saying so beats a `command not found` inside a detached runner that shows
  # up minutes later as `failed(127)`.
  if [ "$tool" = agy ]; then
    command -v agy >/dev/null 2>&1 || die "profile '$profile' needs the agy CLI, which is not installed.
  agy is optional. Either do this task in the orchestrator yourself, or pick a
  ccs profile: oc-smart, oc-fast, oc-free, deepseek."
    model=${model:-$(agy_default_model "$profile")}
  fi

  # Preflight before the worktree exists, so a dead profile leaves nothing to
  # clean up. ~2s to a real error beats 118s to a wrong one.
  if [ "$tool" = ccs ] && [ "${preflight:-yes}" != no ]; then
    local probe
    if ! probe=$(probe_ccs_profile "$profile" "$model"); then
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
  local dir wt branch base_sha sid
  dir=$(slug_dir "$slug"); wt="$dir/worktree"; branch="ccs/$slug"

  [ -e "$wt" ] && die "launch: '$slug' already exists ($wt). Use a new slug, or: fleet.sh clean $slug"
  git -C "$REPO" show-ref --verify --quiet "refs/heads/$branch" \
    && die "launch: branch '$branch' already exists. Use a new slug, or: fleet.sh clean $slug"

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

# --- verify ----------------------------------------------------------------

verify_row() { printf '%-11s %-4s %-6s %s\n' "$1" "$2" "$3" "$4"; }

# Config drift and a live probe, per profile. Reports the upstream's own words
# for a failure and names any way the live config has wandered from the table
# above — a base URL that slid back to the unfunded PAYG path, a model id the
# subscription rejects, a transport that would silently start a proxy daemon.
# Drift is worth printing even when the probe passes: it is how a profile ends
# up quietly serving something other than what the routing table promises.
cmd_verify() {
  local -a profiles=("$@")
  [ ${#profiles[@]} -gt 0 ] || read -r -a profiles <<< "$(profile_names)"

  local rc=0 p tool base_want model_want transport_want
  local base model transport probe drift
  verify_row PROFILE TOOL RESULT DETAIL
  for p in "${profiles[@]}"; do
    tool=$(profile_field "$p" 2)
    if [ -z "$tool" ]; then
      verify_row "$p" "?" FAIL "not a fleet profile (known: $(profile_names))"; rc=1; continue
    fi
    model_want=$(profile_field "$p" 4)

    if [ "$tool" = agy ]; then
      if ! command -v agy >/dev/null 2>&1; then
        verify_row "$p" agy skip "agy not installed — optional, fleet degrades to the orchestrator"
        continue
      fi
      if agy models 2>/dev/null | cut -f1 | grep -qx -- "$model_want"; then
        verify_row "$p" agy ok "$model_want"
      else
        verify_row "$p" agy FAIL "'$model_want' is not in \`agy models\` — the id moved or was retired"; rc=1
      fi
      continue
    fi

    base_want=$(profile_field "$p" 3); transport_want=$(profile_field "$p" 5)
    base=$(ccs_setting "$p" ANTHROPIC_BASE_URL)
    model=$(ccs_setting "$p" ANTHROPIC_MODEL)
    transport=$(ccs_setting "$p" CCS_DROID_PROVIDER)

    if [ -z "$base" ]; then
      verify_row "$p" ccs FAIL "no ~/.ccs/$p.settings.json — run: $(basename "$SELF") provision"; rc=1; continue
    fi

    drift=""
    [ "$base" = "$base_want" ]           || drift+="base=$base (want $base_want); "
    [ "$model" = "$model_want" ]         || drift+="model=$model (want $model_want); "
    [ "$transport" = "$transport_want" ] || drift+="transport=${transport:-unset} (want $transport_want); "

    if probe=$(probe_ccs_profile "$p"); then
      if [ -n "$drift" ]; then
        verify_row "$p" ccs drift "${drift%; }"
      else
        verify_row "$p" ccs ok "$model -> \"$probe\""
      fi
    else
      verify_row "$p" ccs FAIL "$probe"; rc=1
      [ -n "$drift" ] && verify_row "" "" "" "drift: ${drift%; }"
    fi
  done
  return $rc
}

# --- provision -------------------------------------------------------------

# Recreate the ccs side of the fleet from scratch, so a new machine is one
# command. `ccs api create` writes the settings file and registers the profile,
# but it guesses `generic-chat-completion-api` for any base URL it doesn't
# recognise — which would put oc-fast and oc-smart behind a proxy daemon
# they don't need — so the transport and the cheap haiku-tier mapping are
# corrected afterwards.
cmd_provision() {
  local key="${OPENCODE_API_KEY:-}"
  [ -n "$key" ] || die "provision: set OPENCODE_API_KEY to your opencode.ai key first.
  The deepseek profile needs DEEPSEEK_API_KEY too if you want it provisioned."
  command -v ccs >/dev/null 2>&1 || die "provision: the ccs CLI is not installed"

  local p tool base model transport k haiku
  while IFS='|' read -r p tool base model transport; do
    [ "$tool" = ccs ] || continue
    k=$key
    if [ "$p" = deepseek ]; then
      k="${DEEPSEEK_API_KEY:-}"
      [ -n "$k" ] || { printf 'skipping %s (no DEEPSEEK_API_KEY)\n' "$p"; continue; }
    fi
    ccs api create "$p" --base-url "$base" --api-key "$k" --model "$model" \
      --target claude --force --yes >/dev/null 2>&1 \
      || { printf 'provision: ccs api create failed for %s\n' "$p" >&2; continue; }

    # The cheapest model on the same endpoint absorbs Claude Code's background
    # haiku-tier calls, so trivia doesn't burn the tier the task is paying for.
    haiku=$model
    case "$base" in *opencode.ai/zen/go) haiku=deepseek-v4-flash ;; esac
    case "$base" in *api.deepseek.com*)  haiku=deepseek-v4-flash ;; esac
    python3 -c 'import json,sys
path, transport, haiku = sys.argv[1:4]
d = json.load(open(path)); d.setdefault("env", {})
d["env"]["CCS_DROID_PROVIDER"] = transport
d["env"]["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = haiku
json.dump(d, open(path, "w"), indent=2)
open(path, "a").write("\n")' "$HOME/.ccs/$p.settings.json" "$transport" "$haiku" \
      || die "provision: could not finish writing ~/.ccs/$p.settings.json"
    printf 'provisioned %-9s %s  %s (%s)\n' "$p" "$base" "$model" "$transport"
  done < <(fleet_profiles)

  printf '\nnow: %s verify\n' "$(basename "$SELF")"
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
    [ -n "$sid" ] || die "resume: no conversation id recorded for '$slug' yet — check: fleet.sh log $slug"
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

  git -C "$wt" -c commit.gpgsign=false commit -q -m "$(printf 'fleet(%s): %s\n\nDelegated via %s profile %s.\n' \
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
  provision) shift; cmd_provision "$@" ;;
  *) cat <<'USAGE'
fleet.sh — isolated CCS/agy coding agents, one git worktree each

  launch --task <slug> --profile <profile> [--model <m>]
         (--prompt <text> | --prompt-file <path>) [--base <ref>] [--repo <path>]
         [--no-preflight]
         profiles: oc-smart   deepseek-v4-pro    default coding reach
                   oc-fast    deepseek-v4-flash  cheapest, mechanical edits
                   oc-free    hy3-free           throwaway; id rots, check verify
                   deepseek   deepseek-v4-pro[1m]  overflow once go's cap is hit
                   agy-gemini gemini-3.1-pro-high   research, not coding
                   agy-opus   claude-opus-4-6-thinking  frontier escape hatch
  status                       one line per agent: state, tool, profile, files changed
  log <slug>                   raw CCS/agy output for that agent
  diff <slug>                  everything the agent changed, vs. the commit it started from
  resume <slug> --prompt <t>   another turn in the same agent's session, same worktree
  land <slug>                  commit the agent's work and merge its branch into HEAD
  clean <slug> [--force]       delete the worktree, branch, and run state
  verify [profile...]          probe every profile; report upstream errors and config drift
  provision                    (re)create the ccs profiles from OPENCODE_API_KEY

Env: CCS_FLEET_HOME, CCS_FLEET_TIMEOUT (1800s), CCS_FLEET_EXCLUDES_FILE,
     CCS_FLEET_PREFLIGHT_TIMEOUT (20s), CCS_FLEET_NO_PREFLIGHT
USAGE
     exit 1 ;;
esac
