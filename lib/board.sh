# lib/board.sh — what the board and t ui show: rows, colors, the pane, pickers. Sourced by lib/tick.sh.

# the board's colors (Tokyo Night), for t ui and for t log in a terminal
C_GREEN=$'\e[38;2;158;206;106m' C_YELLOW=$'\e[38;2;224;175;104m' C_RED=$'\e[38;2;247;118;142m'
C_BLUE=$'\e[38;2;122;162;247m' C_PURPLE=$'\e[38;2;187;154;247m' C_DIM=$'\e[38;2;86;95;137m'
C_TEXT=$'\e[38;2;169;177;214m' C_OFF=$'\e[0m'
# the same for fzf; the spinner (always on while t ui waits for a change) has the background's color
T_FZF_COLORS='fg:#c0caf5,bg:#1a1b26,fg+:#c0caf5,bg+:#292e42,hl:#7aa2f7,hl+:#7aa2f7,info:#e0af68,prompt:#7aa2f7:bold'
T_FZF_COLORS+=',pointer:#f7768e,separator:#2a2e42,border:#2a2e42,preview-bg:#17171f,preview-border:#2a2e42'
T_FZF_COLORS+=',scrollbar:#2a2e42,header:#565f89,spinner:#1a1b26'

# the C_ colors stay only on a terminal, or with CLICOLOR_FORCE (t ui's pane); elsewhere they print nothing
terminal_colors() {
  if [ -t 1 ] || [ -n "${CLICOLOR_FORCE:-}" ]; then return; fi
  C_GREEN= C_YELLOW= C_RED= C_BLUE= C_PURPLE= C_DIM= C_TEXT= C_OFF=
}

# $2 padded with spaces to $1 characters; bash's printf counts bytes, and ✓ is three.
# $3, when given, is printed in its place: the same text in color.
pad() { printf '%s%*s' "${3:-$2}" $(($1 - ${#2})) ''; }
pad_left() { printf '%*s%s' $(($1 - ${#2})) '' "$2"; }

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
  local t marks width=8
  if [ "${T_STEPS:-}" = names ]; then
    for t in "$T_TASKS"/*/; do
      [ -f "$t/step" ] || continue
      marks=$(progress "${t%/}")
      if [ $((${#marks} + 1)) -gt "$width" ]; then width=$((${#marks} + 1)); fi
    done
  fi
  echo "$width"
}

board_header() { printf '%-4s%-*s%3s  %-5s  %-28s %s\n' ID "$1" STEPS AGE REPO TITLE STATUS; }

# the last line of a step log's latest run worth showing: not its header, a session line, a fence or a blank
last_words() {
  tail -n 40 "$1" 2> /dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '
    /^=== /                      { last = ""; next }
    /^session: |^```/ || NF == 0 { next }
                                 { sub(/^ *(· |! )/, ""); last = $0 }
    END                          { print last }'
}

# what a task is doing: while it runs or will run its step again, that step's latest line; else why not
status() {
  local st step line
  st=$(state "$1") step=$(cat "$1/step")
  case $st in
    HOLD)   echo "HELD $(head -1 "$1/hold")"; return ;;
    after*) echo "$st"; return ;;
    done)   if [ -f "$1/answer.md" ]; then echo answered; else echo done; fi; return ;;
  esac
  line=$(last_words "$1/log/$step.log")
  if [ "$st" = running ]; then echo "${step#*-}: ${line:-starting}"
  elif [ -n "$line" ]; then echo "next tick · ${step#*-}: $line"      # it ran, and runs again
  else echo "next tick"
  fi
}

# how long a task has been on its step (<1m, 12m, 3h, 2d), or — where that says nothing
age() {
  local s
  case $(state "$1") in done | after*) echo —; return ;; esac
  if [ ! -e "$1/log/$(cat "$1/step").log" ] && [ ! -e "$1/hold" ]; then echo —; return; fi
  s=$(( $(printf '%(%s)T' -1) - $(stat -c %Y "$1/step") ))
  if [ "$s" -lt 60 ]; then echo "<1m"
  elif [ "$s" -lt 3600 ]; then echo "$((s / 60))m"
  elif [ "$s" -lt 86400 ]; then echo "$((s / 3600))h"
  else echo "$((s / 86400))d"
  fi
}

# one row per task: open ones, then (with -a) done ones. A task waiting on another sits under it.
board() {
  local t done_rows= width
  width=$(steps_width)
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
# 7   ✓✓▶·     3m  amino  Add a discount code field    review: read client.ts
rows() {
  local t=$1 indent=${2:-} st repo=- marks painted since title says child under
  st=$(state "$t")
  if [ -f "$t/repo" ]; then
    repo=$(profile_of "$(cat "$t/repo")")
    repo=${repo:-$(basename "$(cat "$t/repo")")}
  fi
  marks=$(progress "$t") since=$(age "$t") says=$(status "$t") title=$indent$(name "$t")
  if [ "${#title}" -gt 28 ]; then title=${title:0:27}…; fi
  painted=$marks
  if [ -n "${T_COLOR:-}" ]; then          # t ui: done steps green, where it is yellow; a status in its state's color
    painted=${painted//✓/$C_GREEN✓$C_OFF} painted=${painted//▶/$C_YELLOW▶$C_OFF} painted=${painted//·/$C_DIM·$C_OFF}
    case $st in
      running) says=$C_YELLOW$says ;;
      ready)   if [ "$says" = "next tick" ]; then says=$C_DIM$says; else says=$C_YELLOW$says; fi ;;
      HOLD)    says=$C_RED$says ;;
      done)    says=$C_BLUE$says ;;
      *)       says=$C_DIM$says ;;
    esac
    says+=$C_OFF
  fi
  printf '%-4s' "$(task_num "$t")"
  pad "${width:-8}" "$marks" "$painted"
  pad_left 3 "$since"
  printf '  %-5.5s  ' "$repo"
  pad 28 "$title"
  printf ' %s\n' "$says"

  if [ -z "$indent" ]; then under="└ "; else under="  $indent"; fi
  for child in "$T_TASKS"/*/after; do
    if [ "$(cat "$child" 2> /dev/null)" = "${t##*/}" ] && [[ $(state "${child%/after}") == after* ]]; then
      rows "${child%/after}" "$under"
    fi
  done
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

# the CLI after $1 when ^A cycles it: the pipeline's own (empty), then each driver
next_cli() { next_choice "$1" "" $(ls "$T_ROOT/drivers"); }

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
pane() {
  if [ -n "${2:-}" ]; then echo "$2"
  elif [ "$(state "$1")" = running ]; then echo log
  else echo show
  fi
}

# the pane tab goes to after $2: show, log, then diff when the task has a branch
pane_next() {
  case $2 in
    show) echo log ;;
    log)  if [ -f "$1/branch" ] && git -C "$(cat "$1/repo")" rev-parse -q --verify "refs/heads/$(cat "$1/branch")" > /dev/null 2>&1
          then echo diff; else echo show; fi ;;
    *)    echo show ;;
  esac
}

# a tab strip for t ui's pane: the choices $3..., the one that is $2 in color $1 (no color: in brackets)
strip() {
  local color=$1 current=$2 choice out=
  shift 2
  for choice; do
    if [ "$choice" != "$current" ]; then out+="${color:+$C_DIM}$choice${color:+$C_OFF}  "
    elif [ -n "$color" ]; then out+=$'\e[1m'"$color$choice$C_OFF  "
    else out+="[$choice]  "
    fi
  done
  printf %s "$out"
}

# a line across t ui's pane, in color $1
rule() { printf '%s%s%s\n' "${1:-}" "$(printf '─%.0s' $(seq "${FZF_PREVIEW_COLUMNS:-60}"))" "${1:+$C_OFF}"; }
