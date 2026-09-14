# lib/tick.sh — sourced by every script in bin/: paths, settings, and tasks, pipelines and repos.
# lib/board.sh, sourced from here, is what the board and t ui show.

T_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T_PATH_BEFORE=$PATH
set -a; . "$T_ROOT/etc/tick.conf"; set +a    # every setting, to steps and drivers too
T_TASKS=$T_VAR/tasks
PATH=$T_ROOT/bin:$PATH
export T_ROOT T_VAR T_TASKS PATH
. "$T_ROOT/lib/board.sh"

die() { echo "t: $*" >&2; exit 1; }

# grep -q stops reading at the first match; under pipefail the writer's SIGPIPE then fails the
# pipe though the line matched. Read to the end instead.
matched() { grep "$@" > /dev/null; }

# a task's number from its directory or id: .../tasks/0007 → 7
task_num() { echo $((10#${1##*/})); }

# the directory of task 7
tdir() { echo "$T_TASKS/$(printf %04d "$((10#$1))")"; }

title() { sed -n '1s/^# //p' "$1/task.md"; }

# what the board calls a task: the short name `t name` gave it, else its title
name() { cat "$1/name" 2> /dev/null || title "$1"; }

# done | HOLD | after ID | running | ready
state() {
  local parent
  if [ "$(cat "$1/step")" = done ]; then echo done; return; fi
  if [ -e "$1/hold" ]; then echo HOLD; return; fi
  if [ -f "$1/after" ]; then
    parent=$(cat "$1/after")
    if [ "$(cat "$T_TASKS/$parent/step" 2> /dev/null)" != done ]; then echo "after $(task_num "$parent")"; return; fi
  fi
  if flock -n -s "$1/lock" true 2> /dev/null; then echo ready; else echo running; fi   # shared: two lookers never see each other
}

# stop a task's run now, agent and all: every process of the run holds its lock open
stop() {
  fuser -k -TERM "$1/lock" > /dev/null 2>&1 || true
  if flock -w 10 "$1/lock" true; then return; fi
  fuser -k -KILL "$1/lock" > /dev/null 2>&1 || true
  flock -w 5 "$1/lock" true || die "task $(task_num "$1") still runs; see what holds it: fuser -v $1/lock"
}

# the steps a pipeline leaves out unless a task asks for them: OPTIONAL= in its env
optional() { env_get "$T_ROOT/pipelines/$1/env" OPTIONAL; }

# the steps of a pipeline, in order; its env file is not a step. A second argument leaves out the
# optional steps a task didn't ask for; it is the task's directory (it has a step file), or, before
# there is one, the step names it asked for with +plan.
steps() {
  local want=${2:-} off=
  if [ $# -gt 1 ]; then
    off=$(optional "$1")
    if [ -f "$want/step" ]; then                       # a task: the optional steps it asked for
      if [ -f "$want/opt" ]; then want=$(tr '\n' ' ' < "$want/opt"); else want=; fi
    fi
  fi
  LC_ALL=C ls "$T_ROOT/pipelines/$1" | grep '^[0-9]' | awk -v off=" $off " -v want=" $want " '
    { name = $0; sub(/^[0-9]+-/, "", name) }
    index(off, " " name " ") && !index(want, " " name " ") { next }
    { print }'
}

# the steps task $1 can restart at, by name and in order: its own, and as +name the optional ones it left out
restart_steps() {
  local pipeline mine s
  pipeline=$(cat "$1/pipeline")
  mine=" $(steps "$pipeline" "$1" | xargs) "
  for s in $(steps "$pipeline"); do
    if [[ $mine == *" $s "* ]]; then echo "${s#*-}"; else echo "+${s#*-}"; fi
  done
}

# the step after $2 in pipeline $1 for task $3, or "done"
next_step() {
  local s prev=
  for s in $(steps "$1" "$3"); do
    if [ "$prev" = "$2" ]; then echo "$s"; return; fi
    prev=$s
  done
  echo done
}

# a step of task $3 by name, with or without its number: "review" → "30-review". "done" always exists.
find_step() {
  local s
  if [ "$2" = done ]; then echo done; return; fi
  for s in $(steps "$1" "$3"); do
    if [ "$s" = "$2" ] || [ "${s#*-}" = "$2" ]; then echo "$s"; return; fi
  done
}

# every pipeline, $1 first, then the longest: code before questions
pipelines() {
  local d p rank
  for d in "$T_ROOT"/pipelines/*/; do
    p=$(basename "$d")
    if [ "$p" = "$1" ]; then rank=0; else rank=$((10 - $(steps "$p" | wc -l))); fi
    echo "$rank $p"
  done | sort -k1,1n -k2 | cut -d' ' -f2
}

# one setting from an env file
env_get() {
  if [ ! -f "$1" ]; then return 0; fi
  (unset "$2"; . "$1" > /dev/null 2>&1; echo "${!2:-}")
}

# repos/NAME/env names a repo: REPO= where it is, PIPELINE= its default pipeline, and
# settings its steps read (TEST_CMD=, TEARDOWN=)
profile_get() {
  if [ -n "$1" ]; then env_get "$T_ROOT/repos/$1/env" "$2"; fi
}

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

# the pipeline t new picks by itself in repo $1 (a name or a path; left out, the one you're in)
default_pipeline() {
  local here p
  here=$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null) && here=${here%/.git}
  if [ -n "${1:-}" ]; then here=$(repo_path "$1"); fi
  p=$(profile_get "$(profile_of "$(realpath -m "${here:-.}")")" PIPELINE)
  echo "${p:-$T_PIPELINE}"
}

# a task's env files, the most specific last: its pipeline's, its repo's, its own
env_files() {
  local profile
  profile=$(profile_of "$(cat "$1/repo" 2> /dev/null)")
  printf '%s\n' "$T_ROOT/pipelines/$(cat "$1/pipeline")/env" ${profile:+"$T_ROOT/repos/$profile/env"} "$1/env"
}

# a task's settings: its env files, one after the other
load_env() {
  local f
  while read -r f; do
    if [ -f "$f" ]; then . "$f"; fi
  done < <(env_files "$1")
}

# the CLI that step $2 of pipeline $1 runs on, when the pipeline names one (CLI_<step>=);
# given a task directory as $3, its repo's settings and its own `t new --cli` count too
solver() {
  local var=CLI_${2//[^a-zA-Z0-9_]/_}
  (
    if [ -f "$T_ROOT/pipelines/$1/env" ]; then . "$T_ROOT/pipelines/$1/env" > /dev/null 2>&1; fi
    if [ -n "${3:-}" ]; then load_env "$3" > /dev/null 2>&1; fi
    if [ -n "${!var:-}" ]; then echo "${AGENT_CLI:-${!var}}"; fi
  )
}

# a pipeline's steps with their solvers: implement (opencode) → test → review (opencode).
# An optional step is marked +plan, unless $2 says which of them a task asked for.
flow() {
  local s name who out= mark=
  if [ $# -le 1 ]; then mark=" $(optional "$1") "; fi
  for s in $(steps "$1" ${2+"$2"}); do
    name=${s#*-} who=$(solver "$1" "$name")
    if [[ $mark == *" $name "* ]]; then name=+$name; fi
    out+=" → $name${who:+ ($who)}"
  done
  echo "${out# → }"
}

# a task from what you typed: 42, a word from its title, a path, or nothing (then you choose)
task_dir() {
  local arg=${1:-} matches choice id list
  if [[ $arg =~ ^[0-9]+$ ]]; then
    [ -d "$(tdir "$arg")" ] || die "no task $arg (see: t ls -a)"
    tdir "$arg"
    return
  fi
  if [ -n "$arg" ] && [ -f "$arg/step" ]; then (cd "$arg" && pwd); return; fi

  matches=$(board -a | while IFS= read -r row; do     # the board shows names, so match the titles too
    read -r id _ <<< "$row"
    if { echo "$row"; title "$(tdir "$id")"; } | matched -qiF -- "$arg"; then echo "$row"; fi
  done)
  [ -n "$matches" ] || die "${arg:+no task matches '$arg'}${arg:-there are no tasks yet; start one: t new}"
  choice=$matches
  if [ "$(wc -l <<< "$matches")" -gt 1 ]; then
    list=$(while read -r id _; do echo "  $id  $(title "$(tdir "$id")")"; done <<< "$matches")
    choice=$(PICK_PREVIEW="$T_ROOT/bin/t-show {1}" pick task <<< "$matches") ||
      die "which task? give its number:"$'\n'"$list"
  fi
  read -r id _ <<< "$choice"
  tdir "$id"
}
