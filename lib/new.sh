# lib/new.sh — where a new task goes, and what t new --dry shows of it. Sourced by bin/t-new,
# whose flags ($repo, $pipeline, $base, $on, $from, $cli, $now, $title) these read and fill in.

# the branch a repo's tasks start from: origin's copy first, since a local main may be behind
trunk() {
  local b
  git -C "$1" symbolic-ref -q --short refs/remotes/origin/HEAD && return
  for b in origin/main origin/master main master; do
    if git -C "$1" rev-parse -q --verify "$b^{commit}" > /dev/null; then echo "$b"; return; fi
  done
  return 1
}

# "-add-the-widget", for the branch: the title's first sentence, so the rest can spell the task out
slug() {
  local s=${1%%. *}
  s=$(printf '%s' "${s%.}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-40 | sed 's/^-*//; s/-*$//')
  echo "${s:+-$s}"
}

# the highest task number so far, or 0
last_task_num() {
  local last
  last=$(ls "$T_TASKS" 2> /dev/null | grep -x '[0-9]*' | sort -n | tail -1 || true)   # tasks/ may hold a stray file
  echo $((10#${last:-0}))
}

# what an answered task $1 asked, its follow-ups, and its answer: the details of a task made from it
question_and_answer() {
  local followup
  echo "## The question (task $(task_num "$1"))"
  sed '1s/^# //' "$1/task.md"
  for followup in "$1"/log/feedback.*.md; do
    if [ -f "$followup" ]; then printf '\n## Its follow-up\n\n'; cat "$followup"; fi
  done
  printf '\n## Its answer\n\n'
  cat "$1/answer.md"
}

# grep -q may leave crontab writing, and pipefail would take its SIGPIPE for a no: a subshell's
# exit goes unwatched, so the match alone decides
has_cron_tick() { grep -q 'bin/t tick' <(crontab -l 2> /dev/null); }

# every task needs a repo, but for one whose pipeline says REPO=none and whose -r names none
needs_repo() { [ -n "$repo" ] || [ -z "$pipeline" ] || ! no_repo "$pipeline"; }

# the repo from -r, the pipeline's own REPO=, the directory you're in, or $T_REPO; into $why, which one.
# Then the repo's default pipeline and its trunk, unless -p and --base named them.
find_repo() {
  local pin= common
  if [ -n "$pipeline" ]; then pin=$(env_get "$T_ROOT/pipelines/$pipeline/env" REPO); fi
  if [ -n "$pin" ] && [ "$pin" != none ]; then
    if [ -n "$repo" ] && [ "$(realpath -m "$(repo_path "$repo")")" != "$(realpath -m "$(repo_path "$pin")")" ]; then
      die "$pipeline works only in $pin: leave out -r, or pick another pipeline with -p"
    fi
    repo=$pin why="$pipeline works only here"
  fi
  if [ -n "$repo" ]; then
    repo=$(repo_path "$repo") why=${why:--r}
  elif ! git rev-parse --git-dir > /dev/null 2>&1 && [ -n "$T_REPO" ]; then
    repo=$(repo_path "$T_REPO") why=T_REPO
  fi
  common=$(git -C "${repo:-.}" rev-parse --path-format=absolute --git-common-dir 2> /dev/null) ||
    die "${repo:-this directory} is not in a git repo: cd into one, pass -r NAME, or set T_REPO in etc/tick.conf"
  repo=${common%/.git} why=${why:-this directory}
  if [ -z "$pipeline" ]; then pipeline=$(profile_get "$(profile_of "$repo")" PIPELINE); fi
  if [ -z "$base" ]; then base=$(env_get "$T_ROOT/pipelines/${pipeline:-$T_PIPELINE}/env" TRUNK); fi   # main: the local main it lands on
  if [ -z "$base" ]; then base=$(trunk "$repo") || die "can't tell the trunk of $repo; pass --base BRANCH"; fi
}

row() { printf '%s%-10s%s%s\n' "$C_DIM" "$1" "$C_OFF" "$2"; }

# t new --dry: the task it would make, while you can still change it (t compose's preview)
preview() {
  local n profile def cmd="t new" flags= short sibling want
  terminal_colors
  n=$(( $(last_task_num) + 1 ))

  if [ -n "$repo" ]; then
    profile=$(profile_of "$repo")
    row repo "${profile:-${repo##*/}}$C_DIM   ($why)$C_OFF"
    row pipeline "$pipeline"
    row branch "t/$(printf %04d "$n")$(slug "$title")"
    row base "$base"
  else
    row pipeline "$pipeline"
    row repo "${C_DIM}none needed$C_OFF"
  fi
  row steps "$(AGENT_CLI=$cli flow "$pipeline" "$opt")"
  if [ -n "$now" ]; then row starts "${C_BRIGHT}now, here$C_OFF"
  elif [ -n "$on" ]; then row starts "when task $(task_num "$parent") is done"
  elif has_cron_tick; then row starts "${C_BRIGHT}next tick, < 60s$C_OFF"
  else row starts "${C_RED}only when you run it: there is no cron tick (see t doctor)$C_OFF"
  fi
  if [ -n "$on" ]; then
    row branches "from task $(task_num "$parent")'s branch, into a worktree of its own"
    for sibling in "$T_TASKS"/*/after; do     # a sibling branches from the same task on the same tick
      if [ "$(cat "$sibling" 2> /dev/null)" = "${parent##*/}" ] && [[ $(state "${sibling%/after}") == after* ]]; then
        printf '\n%stask %s is already stacked here and branches from the same place%s\n' "$C_BRIGHT" "$(task_num "${sibling%/after}")" "$C_OFF"
      fi
    done
  fi
  if [ -n "$from" ]; then row details "task $(task_num "$asked")'s question and answer"; fi
  if [ "${#title}" -gt 40 ]; then printf '\n%sname     an agent will pick a short one (title > 40)%s\n' "$C_BRIGHT" "$C_OFF"; fi
  if [ -z "$repo" ] && [ -z "$now" ]; then printf '\n%sthe answer lands in the pane%s\n' "$C_DIM" "$C_OFF"; fi

  def=$(profile_get "$(profile_of "$repo")" PIPELINE)
  if [ -n "$on" ]; then flags+=" --on $(task_num "$parent")"
  elif [ "$pipeline" != "${def:-$T_PIPELINE}" ]; then
    if [ -e "$T_ROOT/bin/t-$pipeline" ]; then flags+=" -p $pipeline"; else cmd="t $pipeline"; fi
  fi
  if [ -n "$from" ]; then flags+=" --from $(task_num "$asked")"; fi
  for want in $opt; do flags+=" +$want"; done
  if [ -n "$repo_arg" ]; then flags+=" -r $repo_arg"; fi
  if [ -n "$cli" ]; then flags+=" --cli $cli"; fi
  if [ -n "$now" ]; then flags+=" --now"; fi
  short=${title:-…}
  if [ "${#short}" -gt 22 ]; then short="${short:0:21}…"; fi
  printf '\n%s%s%s \\\n  "%s"%s\n' "$C_DIM" "$cmd" "$flags" "$short" "$C_OFF"            # the command, to type next time
}
