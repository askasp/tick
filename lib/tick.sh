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

# the repo a pipeline is tied to: REPO= in pipelines/NAME/env
pipeline_repo() {
  local env=$T_ROOT/pipelines/$1/env
  [ -f "$env" ] || return 0
  (REPO=; . "$env" > /dev/null 2>&1; [ -z "$REPO" ] || realpath -m "$REPO")
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
