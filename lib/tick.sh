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

# what the board calls a task: the short name `t name` gave it, else its title
name() { cat "$1/name" 2> /dev/null || title "$1"; }

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

# a task's env files, the most specific last: its pipeline's, its repo's, its own
env_files() {
  local p
  p=$(profile_of "$(cat "$1/repo" 2> /dev/null)")
  printf '%s\n' "$T_ROOT/pipelines/$(cat "$1/pipeline")/env" ${p:+"$T_ROOT/repos/$p/env"} "$1/env"
}

# a task's settings: its env files, one after the other
load_env() {
  local f
  while read -r f; do [ ! -f "$f" ] || . "$f"; done < <(env_files "$1")
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
  elif ! flock -n -s "$1/lock" true 2> /dev/null; then echo running   # shared: two lookers never see each other
  else echo ready
  fi
}

# ✓✓▶·· — the pipeline's steps: behind it, where it is, still to come.
# T_STEPS=names spells them out: ✓ implement  ▶ test  · review
progress() {
  local s m mark=✓ step out=
  step=$(cat "$1/step")
  for s in $(steps "$(cat "$1/pipeline")"); do
    if [ "$s" = "$step" ]; then m=▶ mark=·; else m=$mark; fi
    if [ "${T_STEPS:-}" = names ]; then out+="$m ${s#*-}  "; else out+=$m; fi
  done
  printf %s "${out%  }"
}

# how wide the board's STEPS column is: 8, or with the steps spelled out, the widest task's and a space
steps_width() {
  local t p w=8
  if [ "${T_STEPS:-}" = names ]; then
    for t in "$T_TASKS"/*/; do
      [ -f "$t/step" ] || continue
      p=$(progress "${t%/}"); [ "$((${#p} + 1))" -le "$w" ] || w=$((${#p} + 1))
    done
  fi
  echo "$w"
}

board_header() { printf '%-4s%-*s%3s  %-5s  %-28s %s\n' ID "$1" STEPS AGE REPO TITLE STATUS; }

# the board's colors (Tokyo Night), for t ui and for t log in a terminal
C_GREEN=$'\e[38;2;158;206;106m' C_YELLOW=$'\e[38;2;224;175;104m' C_RED=$'\e[38;2;247;118;142m'
C_BLUE=$'\e[38;2;122;162;247m' C_PURPLE=$'\e[38;2;187;154;247m' C_DIM=$'\e[38;2;86;95;137m'
C_TEXT=$'\e[38;2;169;177;214m' C_OFF=$'\e[0m'
# the same for fzf; the spinner (always on while t ui waits for a change) has the background's color
T_FZF_COLORS='fg:#c0caf5,bg:#1a1b26,fg+:#c0caf5,bg+:#292e42,hl:#7aa2f7,hl+:#7aa2f7,info:#e0af68,prompt:#7aa2f7:bold'
T_FZF_COLORS+=',pointer:#f7768e,separator:#2a2e42,border:#2a2e42,preview-bg:#17171f,preview-border:#2a2e42'
T_FZF_COLORS+=',scrollbar:#2a2e42,header:#565f89,spinner:#1a1b26'

# what a task is doing: while it runs or will run its step again, that step's latest line; else why not
status() {
  local st step line
  st=$(state "$1") step=$(cat "$1/step")
  case $st in
    HOLD)   echo "HELD $(head -1 "$1/hold")"; return ;;
    after*) echo "$st"; return ;;
    done)   if [ -f "$1/answer.md" ]; then echo answered; else echo done; fi; return ;;
  esac
  line=$(tail -n 40 "$1/log/$step.log" 2> /dev/null | sed 's/\x1b\[[0-9;]*m//g' |
    awk '/^=== / { l = ""; next } /^session: |^```/ || !NF { next } { sub(/^ *(· |! )/, ""); l = $0 } END { print l }')
  if [ "$st" = running ]; then echo "${step#*-}: ${line:-starting}"
  elif [ -n "$line" ]; then echo "next tick · ${step#*-}: $line"      # it ran, and runs again
  else echo "next tick"
  fi
}

# how long a task has been on its step (<1m, 12m, 3h, 2d), or — where that says nothing
age() {
  local s
  case $(state "$1") in done | after*) echo —; return ;; esac
  [ -e "$1/log/$(cat "$1/step").log" ] || [ -e "$1/hold" ] || { echo —; return; }
  s=$(( $(printf '%(%s)T' -1) - $(stat -c %Y "$1/step") ))
  if [ "$s" -lt 60 ]; then echo "<1m"; elif [ "$s" -lt 3600 ]; then echo "$((s / 60))m"
  elif [ "$s" -lt 86400 ]; then echo "$((s / 3600))h"; else echo "$((s / 86400))d"; fi
}

# what t ui can do with a task, and its key on the board
ACTIONS='log     ctrl-l  its output, live
say     ctrl-s  send it back to a step with your notes
attach  ctrl-a  take over the agent conversation (its own screen)
stack   ctrl-t  start a task on this one (shared worktree, waits for it to finish)
diff    ctrl-g  the change so far
run     ctrl-r  run it now
hold    ctrl-o  pause it, or unpause it when it is held
name    ctrl-e  change what the board calls it
rm      ctrl-x  delete it and its worktree
path    -       print its worktree'

# the actions worth offering for a task now; Enter does the first
offers() {
  case $(state "$1") in
    running) echo log diff hold ;;
    ready)   if [ -s "$1/log/$(cat "$1/step").log" ]; then echo log run hold; else echo run hold rm; fi ;;
    after*)  echo log rm ;;
    HOLD)    echo say log attach hold ;;
    *)       if [ -f "$1/answer.md" ]; then echo say rm; else echo diff stack say rm; fi ;;
  esac
}

# what t ui's pane shows for a task: $2 once you picked one with tab, else the log while it runs
pane() { if [ -n "${2:-}" ]; then echo "$2"; elif [ "$(state "$1")" = running ]; then echo log; else echo show; fi; }

# a tab strip for t ui's pane: the choices $3..., the one that is $2 in color $1 (no color: in brackets)
strip() {
  local c=$1 cur=$2 x out=
  shift 2
  for x; do
    if [ "$x" != "$cur" ]; then out+="${c:+$C_DIM}$x${c:+$C_OFF}  "
    elif [ -n "$c" ]; then out+=$'\e[1m'"$c$x$C_OFF  "
    else out+="[$x]  "
    fi
  done
  printf %s "$out"
}

# a line across t ui's pane, in color $1
rule() { printf '%s%s%s\n' "${1:-}" "$(printf '─%.0s' $(seq "${FZF_PREVIEW_COLUMNS:-60}"))" "${1:+$C_OFF}"; }

# the pipeline t new picks by itself in repo $1 (a name or a path; left out, the one you're in)
default_pipeline() {
  local here p
  here=$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null) && here=${here%/.git}
  [ -z "${1:-}" ] || here=$(repo_path "$1")
  p=$(profile_get "$(profile_of "$(realpath -m "${here:-.}")")" PIPELINE)
  echo "${p:-$T_PIPELINE}"
}

# every pipeline, $1 first, then the longest: code before questions
pipelines() {
  local d p
  for d in "$T_ROOT"/pipelines/*/; do
    p=$(basename "$d")
    echo "$([ "$p" = "$1" ] && echo 0 || echo $((10 - $(steps "$p" | wc -l)))) $p"
  done | sort -k1,1n -k2 | cut -d' ' -f2
}

# what you typed at t ui's new> or t compose's prompt: t new's flags into $flags, the rest into $title
words() {
  local w=() i
  read -ra w <<< "$1"
  flags=() title=
  for ((i = 0; i < ${#w[@]}; i++)); do
    case ${w[i]} in
      -r | -p | --cli | --on | --base | --test) flags+=("${w[i]}" "${w[i + 1]:-}"); i=$((i + 1)) ;;
      --now) flags+=(--now) ;;
      *)     title+=${title:+ }${w[i]} ;;
    esac
  done
}

# the CLI after $1 when ^A cycles it: the pipeline's own (empty), then each driver
next_cli() {
  { echo; ls "$T_ROOT/drivers"; } | awk -v c="$1" 'NR == 1 { f = $0 } s { print; n = 1; exit } $0 == c { s = 1 } END { if (!n) print f }'
}

# the pane tab goes to after $2: show, steps, log, then diff when the task has a branch
pane_next() {
  case $2 in
    show)  echo steps ;;
    steps) echo log ;;
    log)  if [ -f "$1/branch" ] && git -C "$(cat "$1/repo")" rev-parse -q --verify "refs/heads/$(cat "$1/branch")" > /dev/null 2>&1
          then echo diff; else echo show; fi ;;
    *)    echo show ;;
  esac
}

# one row per task: open ones, then (with -a) done ones. A task waiting on another sits under it.
board() {
  local t later= w
  w=$(steps_width)
  for t in "$T_TASKS"/*/; do
    t=${t%/}
    [ -f "$t/step" ] || continue
    case $(state "$t") in
      after*) ;;
      done)   [ "${1:-}" != -a ] || later+=$(rows "$t")$'\n' ;;
      *)      rows "$t" ;;
    esac
  done
  printf %s "$later"
}

# a task's row, then the rows of the tasks waiting on it, $2 before their titles:
# 7   ✓✓▶·     3m  amino  Add a discount code field    review: read client.ts
rows() {
  local t=$1 st repo=- p pc a title say c
  st=$(state "$t")
  if [ -f "$t/repo" ]; then repo=$(profile_of "$(cat "$t/repo")"); repo=${repo:-$(basename "$(cat "$t/repo")")}; fi
  p=$(progress "$t") a=$(age "$t") say=$(status "$t") title=${2:-}$(name "$t")
  [ "${#title}" -le 28 ] || title=${title:0:27}…
  pc=$p
  if [ -n "${T_COLOR:-}" ]; then          # t ui: done steps green, where it is yellow; a status in its state's color
    pc=${p//✓/$C_GREEN✓$C_OFF} pc=${pc//▶/$C_YELLOW▶$C_OFF} pc=${pc//·/$C_DIM·$C_OFF}
    case $st in
      running) say=$C_YELLOW$say ;;
      ready)   if [ "$say" = "next tick" ]; then say=$C_DIM$say; else say=$C_YELLOW$say; fi ;;
      HOLD)    say=$C_RED$say ;;
      done)    say=$C_BLUE$say ;;
      *)       say=$C_DIM$say ;;
    esac
    say+=$C_OFF
  fi
  printf '%-4s%s%*s%*s%s  %-5.5s  %s%*s %s\n' "$((10#${t##*/}))" "$pc" $((${w:-8} - ${#p})) '' \
    $((3 - ${#a})) '' "$a" "$repo" "$title" $((28 - ${#title})) '' "$say"
  for c in "$T_TASKS"/*/after; do
    [ "$(cat "$c" 2> /dev/null)" = "${t##*/}" ] && [[ $(state "${c%/after}") == after* ]] || continue
    rows "${c%/after}" "${2:+  }${2:-└ }"
  done
}

# the directory of task 7
tdir() { echo "$T_TASKS/$(printf %04d "$((10#$1))")"; }

# cut lines to the terminal's width less $1, so a long title can't wrap and break the table
fit() {
  local w line
  w=$(stty size < /dev/tty 2> /dev/null) && w=$((${w#* } - ${1:-0})) && [ "$w" -gt 1 ] || { cat; return; }
  while IFS= read -r line; do
    if [ "${#line}" -gt "$w" ]; then echo "${line:0:w-1}…"; else echo "$line"; fi
  done
}

# choose one line of stdin: with fzf if it is installed, else from a numbered menu
pick() {
  { : < /dev/tty; } 2> /dev/null || return 1
  if command -v fzf > /dev/null && [ "${T_PICKER:-fzf}" = fzf ]; then
    fzf --prompt "$1> " --height 50% --reverse ${PICK_PREVIEW:+--preview "$PICK_PREVIEW"}
    return
  fi
  local rows row PS3="$1 (number; anything else cancels): "
  mapfile -t rows < <(fit 5)      # room for select's "12) "
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
  rows=$(board -a | while IFS= read -r row; do     # the board shows names, so match the titles too
    if { echo "$row"; title "$(tdir "${row%% *}")"; } | grep -qiF -- "$arg"; then echo "$row"; fi
  done)
  [ -n "$rows" ] || die "${arg:+no task matches '$arg'}${arg:-there are no tasks yet; start one: t new}"
  local choice=$rows id list
  if [ "$(wc -l <<< "$rows")" -gt 1 ]; then
    list=$(while read -r id _; do echo "  $id  $(title "$(tdir "$id")")"; done <<< "$rows")
    choice=$(PICK_PREVIEW="$T_ROOT/bin/t-show {1}" pick task <<< "$rows") ||
      die "which task? give its number:"$'\n'"$list"
  fi
  tdir "${choice%% *}"
}
