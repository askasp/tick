# lib/tick.sh — sourced by every script in bin/: paths, settings and a few helpers.

T_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$T_ROOT/etc/tick.conf"
T_TASKS=$T_VAR/tasks
PATH=$T_ROOT/bin:$PATH
export T_ROOT T_VAR T_TASKS PATH

die() { echo "t: $*" >&2; exit 1; }

# 42, 0042 or a path → the task's directory
task_dir() {
  if [[ $1 =~ ^[0-9]+$ ]]; then
    local d; d=$T_TASKS/$(printf %04d "$((10#$1))")
    [ -d "$d" ] || die "no task $1 (see: t ls)"
    echo "$d"
  elif [ -f "$1/step" ]; then
    (cd "$1" && pwd)
  else
    die "not a task: $1"
  fi
}

# the steps of a pipeline, in order
steps() { LC_ALL=C ls "$T_ROOT/pipelines/$1"; }

# the step after $2 in pipeline $1, or "done"
next_step() {
  steps "$1" | awk -v s="$2" 'f { print; n = 1; exit } $0 == s { f = 1 } END { if (!n) print "done" }'
}

# a step by name, with or without its number: "review" → "30-review". "done" always exists.
find_step() {
  if [ "$2" = done ]; then echo done; return; fi
  steps "$1" | awk -v n="$2" '$0 == n || substr($0, index($0, "-") + 1) == n { print; exit }'
}

# the first line of task.md, without the "# "
title() { sed -n '1s/^# //p' "$1/task.md"; }
