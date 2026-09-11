# lib/tick.sh — sourced by every script in bin/: paths, settings and helpers.

T_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T_PATH_BEFORE=$PATH
. "$T_ROOT/etc/tick.conf"
T_TASKS=$T_VAR/tasks
PATH=$T_ROOT/bin:$PATH
export T_ROOT T_VAR T_TASKS PATH

die() { echo "t: $*" >&2; exit 1; }

# the steps of a pipeline, in order; its env file is not a step
steps() { LC_ALL=C ls "$T_ROOT/pipelines/$1" | grep '^[0-9]'; }

# the step after $2 in pipeline $1, or "done"
next_step() {
  steps "$1" | awk -v s="$2" 'f { print; n = 1; exit } $0 == s { f = 1 } END { if (!n) print "done" }'
}

# a step by name, with or without its number: "review" → "30-review". "done" always exists.
find_step() {
  if [ "$2" = done ]; then echo done; return; fi
  steps "$1" | awk -v n="$2" '$0 == n || substr($0, index($0, "-") + 1) == n { print; exit }'
}

title() { sed -n '1s/^# //p' "$1/task.md"; }

# one setting from an env file
env_get() { [ -f "$1" ] || return 0; (unset "$2"; . "$1" > /dev/null 2>&1; echo "${!2:-}"); }

# repos/NAME/env names a repo: REPO= where it is, PIPELINE= its default pipeline, and
# settings its steps read (TEST_CMD=, TEARDOWN=)
profile_get() { [ -z "$1" ] || env_get "$T_ROOT/repos/$1/env" "$2"; }

# the repo profile whose REPO is this path, if there is one
profile_of() {
  local d r
  for d in "$T_ROOT"/repos/*/; do
    d=${d%/}
    r=$(profile_get "${d##*/}" REPO)
    if [ -n "$r" ] && [ "$(realpath -m "$r")" = "$1" ]; then echo "${d##*/}"; return; fi
  done
}

# -r NAME: a repo profile, a path, or a directory in $T_REPOS
repo_path() {
  if [ -f "$T_ROOT/repos/$1/env" ]; then profile_get "$1" REPO
  elif [ -d "$1" ]; then echo "$1"
  elif [ -d "$T_REPOS/$1" ]; then echo "$T_REPOS/$1"
  else die "no repo '$1': not in $T_ROOT/repos/, not a path, and not in $T_REPOS"
  fi
}

# a pipeline that needs no repo says REPO=none in its env (research)
no_repo() { [ "$(env_get "$T_ROOT/pipelines/$1/env" REPO)" = none ]; }

# a task's settings, the most specific last: its pipeline's env, its repo's, its own
load_env() {
  local p f
  p=$(profile_of "$(cat "$1/repo" 2> /dev/null)")
  for f in "$T_ROOT/pipelines/$(cat "$1/pipeline")/env" ${p:+"$T_ROOT/repos/$p/env"} "$1/env"; do
    [ ! -f "$f" ] || . "$f"
  done
}

# the CLI that step $2 of pipeline $1 runs on, when the pipeline names one (CLI_<step>=);
# given a task directory as $3, its repo's settings and its own `t new --cli` count too
solver() {
  local v=CLI_${2//[^a-zA-Z0-9_]/_}
  (
    [ ! -f "$T_ROOT/pipelines/$1/env" ] || . "$T_ROOT/pipelines/$1/env" > /dev/null 2>&1
    [ -z "${3:-}" ] || load_env "$3" > /dev/null 2>&1
    [ -z "${!v:-}" ] || echo "${AGENT_CLI:-${!v}}"
  )
}

# a pipeline's steps with their solvers: implement (opencode) → test → review (opencode)
flow() {
  local s who out=
  for s in $(steps "$1"); do who=$(solver "$1" "${s#*-}"); out+=" → ${s#*-}${who:+ ($who)}"; done
  echo "${out# → }"
}

# done | HOLD | after ID | running | ready
state() {
  if [ "$(cat "$1/step")" = done ]; then echo done
  elif [ -e "$1/hold" ]; then echo HOLD
  elif [ -f "$1/after" ] && [ "$(cat "$T_TASKS/$(cat "$1/after")/step" 2> /dev/null)" != done ]; then echo "after $((10#$(cat "$1/after")))"
  elif ! flock -n "$1/lock" true 2> /dev/null; then echo running
  else echo ready
  fi
}

# ✓✓▶·· — the pipeline's steps: behind it, where it is, still to come
progress() {
  local s mark=✓ step
  step=$(cat "$1/step")
  for s in $(steps "$(cat "$1/pipeline")"); do
    if [ "$s" = "$step" ]; then printf ▶; mark=·; else printf %s "$mark"; fi
  done
}

# one row per task: open ones, then (with -a) done ones
board() {
  local t st p row later=
  for t in "$T_TASKS"/*/; do
    [ -f "$t/step" ] || continue
    t=${t%/}
    st=$(state "$t")
    p=$(progress "$t")
    row=$(printf '%-5s %-8s %s%*s %-13s %-9s %s' "$((10#${t##*/}))" "$(cat "$t/pipeline")" "$p" $((7 - ${#p})) '' \
      "$(cat "$t/step")" "$st" "$(title "$t")")
    if [ "$st" != done ]; then echo "$row"; elif [ "${1:-}" = -a ]; then later+=$row$'\n'; fi
  done
  printf %s "$later"
}

# the directory of task 7
tdir() { echo "$T_TASKS/$(printf %04d "$((10#$1))")"; }

# choose one line of stdin: with fzf if it is installed, else from a numbered menu
pick() {
  { : < /dev/tty; } 2> /dev/null || return 1
  if command -v fzf > /dev/null && [ "${T_PICKER:-fzf}" = fzf ]; then
    fzf --prompt "$1> " --height 50% --reverse ${PICK_PREVIEW:+--preview "$PICK_PREVIEW"}
    return
  fi
  local rows row PS3="$1 (number; anything else cancels): "
  mapfile -t rows
  select row in "${rows[@]}"; do
    [ -n "$row" ] && echo "$row"
    return
  done < /dev/tty
}

# a task from what you typed: 42, a word from its title, a path, or nothing (then you choose)
task_dir() {
  local arg=${1:-} rows
  if [[ $arg =~ ^[0-9]+$ ]]; then
    [ -d "$(tdir "$arg")" ] || die "no task $arg (see: t ls -a)"
    tdir "$arg"
    return
  fi
  if [ -n "$arg" ] && [ -f "$arg/step" ]; then (cd "$arg" && pwd); return; fi
  rows=$(board -a | grep -iF -- "$arg")
  [ -n "$rows" ] || die "${arg:+no task matches '$arg'}${arg:-there are no tasks yet; start one: t new}"
  local choice=$rows id list
  if [ "$(wc -l <<< "$rows")" -gt 1 ]; then
    list=$(while read -r id _; do echo "  $id  $(title "$(tdir "$id")")"; done <<< "$rows")
    choice=$(PICK_PREVIEW="$T_ROOT/bin/t-show {1}" pick task <<< "$rows") ||
      die "which task? give its number:"$'\n'"$list"
  fi
  tdir "${choice%% *}"
}
