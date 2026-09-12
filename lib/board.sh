# lib/board.sh — what the board and t ui show: rows, colors, the pane, pickers. Sourced by lib/tick.sh.

# the board's colors: greys, and one red for what needs you. For t ui, and for t log in a terminal.
C_BRIGHT=$'\e[38;2;242;242;242m' C_TEXT=$'\e[38;2;196;196;196m' C_MID=$'\e[38;2;168;168;168m'
C_DIM=$'\e[38;2;138;138;138m' C_FAINT=$'\e[38;2;110;110;110m' C_RED=$'\e[38;2;208;112;112m' C_OFF=$'\e[0m'
# the same for fzf; the spinner (always on while t ui waits for a change) has the background's color
T_FZF_COLORS='fg:#c4c4c4,bg:#1c1c1c,fg+:#f2f2f2:regular,bg+:#2e2e2e,hl:#f2f2f2:underline,hl+:#f2f2f2:underline'
T_FZF_COLORS+=',prompt:#8a8a8a:regular,query:#c4c4c4,info:#5a5a5a,pointer:#c07070,marker:#c07070,border:#2e2e2e'
T_FZF_COLORS+=',preview-bg:#191919,preview-border:#2e2e2e,scrollbar:#323232,header:#6e6e6e,footer:#6e6e6e,spinner:#1c1c1c'
T_FZF_COLORS+=',input-border:#1c1c1c,footer-border:#1c1c1c'
# fzf as the board and its screens look: fzf's own pointer, air around the prompt (borders in the
# background's color, the separator in spaces), and keys at the bottom. t doctor checks fzf knows them.
BOARD_FZF=(--ansi --reverse --no-sort --with-shell 'bash -c' --color "$T_FZF_COLORS" --pointer '>' --gutter ' '
  --ellipsis '…' --separator ' ' --input-border horizontal --footer-border line)

# the C_ colors stay only on a terminal, or with CLICOLOR_FORCE (t ui's pane); elsewhere they print nothing
terminal_colors() {
  if [ -t 1 ] || [ -n "${CLICOLOR_FORCE:-}" ]; then return; fi
  C_BRIGHT= C_TEXT= C_MID= C_DIM= C_FAINT= C_RED= C_OFF=
}

# $2 padded with spaces to $1 characters; bash's printf counts bytes, and … is three.
# $3, when given, is printed in its place: the same text in color.
pad() { printf '%s%*s' "${3:-$2}" $(($1 - ${#2})) ''; }

# whether the step a task is on has begun: it runs, ran, or was held there
started() { [ -e "$1/log/$(cat "$1/step").log" ] || [ -e "$1/hold" ]; }

# how far a task is: the step it is on of its pipeline's steps (2/4), or while that one hasn't begun,
# the steps behind it (0/4 before the first; 4/4 done)
fraction() {
  local step all at=0 s
  step=$(cat "$1/step") all=$(steps "$(cat "$1/pipeline")" "$1")
  for s in $all; do
    at=$((at + 1))
    [ "$s" = "$step" ] || continue
    if ! started "$1"; then at=$((at - 1)); fi
    break
  done
  echo "$at/$(wc -w <<< "$all")"
}

# the last line of a step log's latest run worth showing: not its header, a session line, a fence or a blank
last_words() {
  tail -n 40 "$1" 2> /dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '
    /^=== /                      { last = ""; next }
    /^session: |^```/ || NF == 0 { next }
                                 { sub(/^ *(· |! )/, ""); last = $0 }
    END                          { print last }'
}

# a long path keeps its end, which says the most: frontend/lib/wearables/workers/notify.ts → …/workers/notify.ts
path_ends() {
  local words word parts out=()
  read -ra words <<< "$1"
  for word in "${words[@]}"; do
    IFS=/ read -ra parts <<< "$word"
    if [ ${#parts[@]} -gt 3 ]; then word="…/${parts[-2]}/${parts[-1]}"; fi
    out+=("$word")
  done
  echo "${out[*]}"
}

# what a task is doing, its state's word first: held and why, after 7, answered, done; while it runs,
# its step and that step's latest line (review  read cart.js); else next tick, and why it runs again
status() {
  local st step line
  st=$(state "$1") step=$(cat "$1/step")
  case $st in
    HOLD)   echo "held  $(head -1 "$1/hold")"; return ;;
    after*) echo "$st"; return ;;
    done)   if [ -f "$1/answer.md" ]; then echo answered; else echo done; fi; return ;;
  esac
  line=$(path_ends "$(last_words "$1/log/$step.log")")
  if [ "$st" = running ]; then echo "${step#*-}  ${line:-starting}"
  elif [ -n "$line" ]; then echo "next tick  ${step#*-}: $line"      # it ran, and runs again
  else echo "next tick"
  fi
}

# how long a task has been on its step (<1m, 12m, 3h, 2d); nothing where that says nothing
age() {
  local s
  case $(state "$1") in done | after*) return ;; esac
  started "$1" || return 0
  s=$(( $(printf '%(%s)T' -1) - $(stat -c %Y "$1/step") ))
  if [ "$s" -lt 60 ]; then echo "<1m"
  elif [ "$s" -lt 3600 ]; then echo "$((s / 60))m"
  elif [ "$s" -lt 86400 ]; then echo "$((s / 3600))h"
  else echo "$((s / 86400))d"
  fi
}

# one row per task: open ones, then (with -a) done ones. A task waiting on another sits under it.
board() {
  local t done_rows=
  for t in "$T_TASKS"/*/; do
    t=${t%/}
    [ -f "$t/step" ] || continue
    case $(state "$t") in
      after*) ;;
      done)   if [ "${1:-}" = -a ]; then done_rows+=$(rows "$t")$'\n'; fi ;;
      *)      rows "$t" ;;
    esac
  done
  printf %s "$done_rows"
}

# a task's row, then the rows of the tasks waiting on it, indented by $2:
#   7  amino   Add a discount code field       3/4    3m  review  read client.ts
# In color (T_COLOR=1, t ui's) it is greys, and red for held: the one thing on the board that needs you.
rows() {
  local t=$1 indent=${2:-} st repo= title since says numbers child under
  if [ -z "${T_COLOR:-}" ]; then local C_TEXT= C_MID= C_DIM= C_FAINT= C_RED= C_OFF=; fi
  numbers=$C_DIM st=$(state "$t")
  if [ -f "$t/repo" ]; then
    repo=$(profile_of "$(cat "$t/repo")")
    repo=${repo:-$(basename "$(cat "$t/repo")")}
  fi
  title=$indent$(name "$t") since=$(age "$t") says=$(status "$t")
  if [ "${#title}" -gt 30 ]; then title=${title:0:29}…; fi
  if [ -n "$since" ]; then numbers=$C_MID; fi
  case $st in
    HOLD)    says=${C_RED}held$C_TEXT${says#held} ;;
    running) says=$C_TEXT$says ;;
    *)       says=$C_DIM$says ;;
  esac
  line "$(task_num "$t")" "$repo" "$title" "$numbers" "$(fraction "$t")" "$since" "$says$C_OFF"

  if [ -z "$indent" ]; then under="└ "; else under="  $indent"; fi
  for child in "$T_TASKS"/*/after; do
    if [ "$(cat "$child" 2> /dev/null)" = "${t##*/}" ] && [[ $(state "${child%/after}") == after* ]]; then
      rows "${child%/after}" "$under"
    fi
  done
}

# one line of the board: id, repo, title, step, age, status, in the columns that fit in $T_COLS (unset:
# all of them). A narrow board drops the repo first, then the status, then the age; never the step.
line() {   # id repo title color-of-the-numbers step age status
  local room=${T_COLS:-999} left=40
  printf '%s%3s%s  ' "$C_DIM" "$1" "$C_OFF"
  if [ "$room" -ge 100 ]; then printf '%s%-6.6s%s  ' "$C_FAINT" "$2" "$C_OFF"; fi
  pad 30 "$3"
  printf '  %s%3s' "$4" "$5"
  if [ "$room" -ge $((left + 6)) ]; then printf '  %4s' "$6"; fi
  printf %s "$C_OFF"
  if [ "$room" -ge $((left + 6 + 22)) ]; then printf '  %s' "$7"; fi
  echo
}

# cut lines to the terminal's width less $1, so a long title can't wrap and break the table
fit() {
  local cols line
  read -r _ cols < <(stty size < /dev/tty 2> /dev/null) || { cat; return; }
  cols=$((cols - ${1:-0}))
  if [ "$cols" -le 1 ]; then cat; return; fi
  while IFS= read -r line; do
    if [ "${#line}" -gt "$cols" ]; then echo "${line:0:cols-1}…"; else echo "$line"; fi
  done
}

# choose one line of stdin: with fzf if it is installed, else from a numbered menu
pick() {
  { : < /dev/tty; } 2> /dev/null || return 1
  if command -v fzf > /dev/null && [ "${T_PICKER:-fzf}" = fzf ]; then
    fzf --prompt "$1> " --height 50% --reverse ${PICK_PREVIEW:+--preview "$PICK_PREVIEW"}
    return
  fi
  local lines line PS3="$1 (number; anything else cancels): "
  mapfile -t lines < <(fit 5)      # room for select's "12) "
  select line in "${lines[@]}"; do
    if [ -n "$line" ]; then echo "$line"; fi
    return
  done < /dev/tty
}

# the choice after $1 among the rest, going round to the first
next_choice() {
  local current=$1 i
  shift
  local choices=("$@")
  for ((i = 0; i < ${#choices[@]} - 1; i++)); do
    if [ "${choices[i]}" = "$current" ]; then echo "${choices[i + 1]}"; return; fi
  done
  echo "${choices[0]}"
}

# the CLI after $1 when ^s cycles it: the pipeline's own (empty), then each driver
next_cli() { next_choice "$1" "" $(ls "$T_ROOT/drivers"); }

# what you typed at t ui's new> or t compose's prompt: t new's flags (+plan too) into $flags, the rest into $title
words() {
  local w=() i
  read -ra w <<< "$1"
  flags=() title=
  for ((i = 0; i < ${#w[@]}; i++)); do
    case ${w[i]} in
      -r | -p | --cli | --on | --base | --test) flags+=("${w[i]}" "${w[i + 1]:-}"); i=$((i + 1)) ;;
      --now) flags+=(--now) ;;
      +*)    flags+=("${w[i]}") ;;                  # +plan: one of the pipeline's optional steps
      *)     title+=${title:+ }${w[i]} ;;
    esac
  done
}

# what t ui can do with a task, and its key on the board. Keys are ctrl- only: over ssh from a Mac, alt-
# arrives only if the terminal sends Option as Meta. The rest are a word away, in the pane ? opens.
ACTIONS='log     ctrl-l  its output, live; again: all of it, unfolded
say     ctrl-y  send it back to a step with your notes
attach  ctrl-o  take over the agent conversation (its own screen)
stack   ctrl-t  start a task that branches from this one (waits for it to finish)
diff    -       the change so far
run     -       run it now
hold    ctrl-r  pause it after this step, or unpause it when it is held
cancel  -       stop its agent now, and hold it
name    -       change what the board calls it
rm      -       delete it and its worktree
path    -       print its worktree'

# the board's keys besides the actions', and a form's (new, stack and say on the board, and t compose).
# Every key is here once: t ui binds it from here, and what the screens say about it comes from here.
BOARD_KEYS='new      ctrl-n  a new task
keys     ?       every action, in the pane'
FORM_KEYS='agent    ctrl-s  another agent than its pipeline names
details  ctrl-o  the details, in $EDITOR
repo     ctrl-r  another repo'

# the key for $1 as fzf binds it (key_of agent → ctrl-s), and as the screens write it (key agent → ^s)
key_of() { printf '%s\n' "$ACTIONS" "$BOARD_KEYS" "$FORM_KEYS" | awk -v n="$1" '$1 == n { print $2; exit }'; }
key() { keyname "$(key_of "$1")"; }

# how t ui writes a key: ctrl-l as ^l, and a key an action hasn't (-) as nothing
keyname() { if [ "$1" != - ]; then echo "${1/#ctrl-/^}"; fi; }

# keys and what they do, for a screen's bottom line: hint enter create esc back → "enter:create   esc:back"
hint() {
  local out=
  while [ $# -ge 2 ]; do out+="$1:$2   "; shift 2; done
  printf %s "${out%   }"
}

# the actions worth offering for a task now; Enter does the first
offers() {
  case $(state "$1") in
    running) echo log diff cancel hold ;;
    ready)   if [ -s "$1/log/$(cat "$1/step").log" ]; then echo log run hold; else echo run hold rm; fi ;;
    after*)  echo log rm ;;
    HOLD)    echo say log attach hold ;;
    *)       if [ -f "$1/answer.md" ]; then echo say rm; else echo diff stack say rm; fi ;;
  esac
}

# what t ui's pane shows for a task: $2 once you picked one with tab, else the log while it runs
pane() {
  if [ -n "${2:-}" ]; then echo "$2"
  elif [ "$(state "$1")" = running ]; then echo log
  else echo show
  fi
}

# the pane tab goes to after $2: show, steps, log, then diff when the task has a branch
pane_next() {
  case $2 in
    show)  echo steps ;;
    steps) echo log ;;
    log | raw)
           if [ -f "$1/branch" ] && git -C "$(cat "$1/repo")" rev-parse -q --verify "refs/heads/$(cat "$1/branch")" > /dev/null 2>&1
           then echo diff; else echo show; fi ;;
    *)     echo show ;;
  esac
}

# a tab strip for t ui's pane: the choices $2..., the one that is $1 bright (no color: in brackets)
strip() {
  local current=$1 choice out=
  shift
  for choice; do
    if [ "$choice" != "$current" ]; then out+="$C_FAINT$choice$C_OFF  "
    elif [ -n "$C_OFF" ]; then out+="$C_BRIGHT$choice$C_OFF  "
    else out+="[$choice]  "
    fi
  done
  printf %s "$out"
}
