# lib/board.sh — what the board and t ui show: rows, colors, the pane, pickers. Sourced by lib/tick.sh.

# the board's colors: greys, and one red for what needs you. For t ui, and for t log in a terminal.
C_BRIGHT=$'\e[38;2;242;242;242m' C_TEXT=$'\e[38;2;196;196;196m' C_MID=$'\e[38;2;168;168;168m'
C_DIM=$'\e[38;2;138;138;138m' C_FAINT=$'\e[38;2;110;110;110m' C_RED=$'\e[38;2;208;112;112m' C_OFF=$'\e[0m'
# the same for fzf; the spinner (always on while t ui waits for a change) has the background's color
T_FZF_COLORS='fg:#c4c4c4,bg:#1c1c1c,fg+:#f2f2f2:regular,bg+:#2e2e2e,hl:#f2f2f2:underline,hl+:#f2f2f2:underline'
T_FZF_COLORS+=',prompt:#8a8a8a:regular,query:#c4c4c4,info:#5a5a5a,pointer:#c07070,marker:#c07070,border:#2e2e2e'
T_FZF_COLORS+=',preview-bg:#191919,preview-border:#2e2e2e,scrollbar:#323232,header:#6e6e6e,footer:#6e6e6e,spinner:#1c1c1c'
T_FZF_COLORS+=',input-border:#1c1c1c,list-border:#1c1c1c,footer-border:#1c1c1c'
# fzf as the board and its screens look: fzf's own pointer, air around the prompt (borders in the
# background's color, the separator in spaces), and keys at the bottom. t doctor checks fzf knows them.
BOARD_FZF=(--ansi --reverse --no-sort --with-shell 'bash -c' --color "$T_FZF_COLORS" --pointer '>' --gutter ' '
  --ellipsis '…' --separator ' ' --input-border horizontal --footer-border line)
# a screen's pane scrolls as the board's: ^d/^u half a page, PgDn/PgUp a page, Shift-↓/↑ a line
PANE_SCROLL=(--bind 'ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up,page-down:preview-page-down,page-up:preview-page-up'
  --bind 'shift-down:preview-down,shift-up:preview-up')

# the C_ colors stay only on a terminal, or with CLICOLOR_FORCE (t ui's pane); elsewhere they print nothing
terminal_colors() {
  if [ -t 1 ] || [ -n "${CLICOLOR_FORCE:-}" ]; then return; fi
  C_BRIGHT= C_TEXT= C_MID= C_DIM= C_FAINT= C_RED= C_OFF=
}

# $2 padded with spaces to $1 characters; bash's printf counts bytes, and … is three.
# $3, when given, is printed in its place: the same text in color.
pad() { printf '%s%*s' "${3:-$2}" $(($1 - ${#2})) ''; }

# a thread.md as the inbox pane draws it: who and when over each message, each comment indented and dimmer
# under the message it follows, one blank line at most, and no "On … wrote:" left behind by a quote.
# Lines fold on words to $FZF_PREVIEW_COLUMNS, so a comment's text stays in its column.
thread_view() {
  awk -v today="$(date '+%a %d %b')" -v cols="${FZF_PREVIEW_COLUMNS:-0}" -v text="$C_TEXT" -v mid="$C_MID" \
      -v dim="$C_DIM" -v faint="$C_FAINT" -v off="$C_OFF" '
    function when(at) { return substr(at, 1, 10) == today ? substr(at, 12) : at }
    function header(line, by, lead,   who, at) {
      who = line; sub(by, "", who); sub(/, [^,]*$/, "", who)
      at = line; sub(/.*, /, "", at)
      if (said) print ""
      print lead who off "  " faint when(at) off
      said = 1; fresh = 1; gap = 0
    }
    function body(s,   lead, n, i, words, line) {
      if (gap && !fresh) print ""
      gap = 0; fresh = 0; said = 1
      lead = s; sub(/[^ ].*/, "", lead)
      n = split(s, words, " ")
      for (i = 1; i <= n; i++) {
        if (line != "" && cols > 0 && length(indent lead line " " words[i]) >= cols) { print color indent lead line off; line = "" }
        line = line == "" ? words[i] : line " " words[i]
      }
      print color indent lead line off
    }
    function release() { if (quoting != "") body(quoting); quoting = "" }
    { sub(/[ \t\r]+$/, "") }
    NR == 1 && /^# / { next }
    /^## / { release(); header(substr($0, 4), "^[^ ]* from ", mid); indent = ""; color = text; next }
    /^### └ comment by / { release(); header(substr($0, 5), "^└ comment by ", "  " faint "└ " dim); indent = "    "; color = dim; next }
    /^_[0-9]+ comments?: .*_$/ { release(); print ""; print faint substr($0, 2, length($0) - 2) off; next }
    /^On .*(wrote|skrev):$/ { next }
    quoting != "" && /(wrote|skrev):$/ { quoting = ""; next }
    { release() }
    /^On / { quoting = $0; next }
    /^$/ { gap = 1; next }
    { body($0) }
    END { release() }' "$1"
}

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
    /^tokens[:\/]/              { next }
    /^mindset [0-9]+\/[0-9]+: / { next }
                                  { sub(/^ *(· |! )/, ""); last = $0 }
    END                          { print last }'
}

# the mindset a review's latest run is reading with, and how many it has (tests 2/3); nothing outside one
mindset_of() {
  tac "$1" 2> /dev/null | awk '
    /^=== /                     { exit }
    /^mindset [0-9]+\/[0-9]+: / { sub(/:$/, "", $2); print $3, $2; exit }'
}

# what a log line says the agent is doing, in a column's worth: a path by its basename, since the
# directory is never the part you needed, and so a command by its verb and the file it names:
#   Read frontend/types/records.types.d.ts                      → Read records.types.d.ts
#   Bash cd "$(git rev-parse --show-toplevel)" && ./ci.sh 2>&1  → Bash ci.sh
doing() {
  local words word out=$1
  read -ra words <<< "$1"
  for word in "${words[@]:1}"; do
    if [[ $word == */* ]]; then out="${words[0]} ${word##*/}"; break; fi
  done
  if [ "${#out}" -gt 32 ]; then out=${out:0:31}…; fi
  echo "$out"
}

# GPU stats if nvidia-smi is available: "GPU 45% 8.1/16.0GiB"
gpu_stats() {
  command -v nvidia-smi > /dev/null 2>&1 || return 0
  nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total \
    --format=csv,noheader,nounits 2>/dev/null | \
    awk -F', ' '{ printf "GPU %d%% %.1f/%.1fGiB\n", $1, $2/1024, $3/1024 }'
}

# the latest token info from a task's step log, for the board footer: "tokens/s: 1234" or "tokens: 9214"
token_rate() {
  local t=$1 step log
  step=$(cat "$t/step" 2>/dev/null)
  [ -n "$step" ] || return 0
  log="$t/log/$step.log"
  [ -f "$log" ] || return 0
  grep -E 'tokens(/s)?:' "$log" 2>/dev/null | tail -1
}

# the line the boards draw under their rows: the GPU stats, and the token rate of the running tasks, if available
board_stats() {
  local t stats= rate
  stats=$(gpu_stats | awk 'NF { printf "%s%s", (n ? "  " : ""), $0; n++ }')
  for t in "$T_TASKS"/*/; do
    [ -f "$t/step" ] || continue
    [ "$(state "$t")" = running ] || continue
    rate=$(token_rate "$t")
    [ -n "$rate" ] && stats="${stats:+$stats  }$rate"
  done
  echo "$stats"
}

# where a task stands, in a word or two: held and why, after 7, answered, done, else the step it is on.
standing() {
  local st step
  st=$(state "$1") step=$(cat "$1/step")
  case $st in
    HOLD)   echo "held  $(head -1 "$1/hold")" ;;
    after*) echo "$st" ;;
    done)   if [ -f "$1/answer.md" ]; then echo answered; else echo done; fi ;;
    *)      echo "${step#*-}" ;;
  esac
}

# what a task is doing: where it stands, and on a step, that step's latest line
# (review  read records.types.d.ts); before it has run, next tick, and why it runs again.
# A job working on a task writes what it is doing into the task's `note`, and that wins while
# it is there: a finished task says done until something is reading it.
status() {
  local st step line mindset
  if [ -s "$1/note" ]; then head -1 "$1/note"; return; fi
  st=$(state "$1") step=$(cat "$1/step")
  case $st in ready | running) ;; *) standing "$1"; return ;; esac
  line=$(doing "$(last_words "$1/log/$step.log")")
  if [ "$st" = running ]; then
    mindset=$(mindset_of "$1/log/$step.log")
    echo "${step#*-}  ${mindset:+$mindset  }${line:-starting}"
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

# a task that watches something and never ends: its step keeps what it watches in inbox, calendar or roadmap
watching() { [ -f "$1/inbox" ] || [ -f "$1/calendar" ] || [ -f "$1/roadmap" ]; }

# one row per task: the watches, the other open ones, then (with -a) done ones. A task waiting on another sits under it.
board() {
  local t open_rows= done_rows=
  for t in "$T_TASKS"/*/; do
    t=${t%/}
    [ -f "$t/step" ] || continue
    case $(state "$t") in
      after*) ;;
      done)   if [ "${1:-}" = -a ]; then done_rows+=$(rows "$t")$'\n'; fi ;;
      *)      if watching "$t"; then rows "$t"; else open_rows+=$(rows "$t")$'\n'; fi ;;
    esac
  done
  printf %s "$open_rows$done_rows"
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
  title=$indent$(name "$t") since=$(age "$t")
  says=$(status "$t")
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
stack   ctrl-t  start a task that branches from this one (waits for it to finish); on an answer, one made from it
diff    -       the files it changed, with the diff of each beside them
run     -       run it now
hold    ctrl-r  pause it after this step, or unpause it when it is held
cancel  -       stop its agent now, and hold it
name    -       change what the board calls it
rm      ctrl-x  delete it and its worktree
path    -       print its worktree
agent   ctrl-s  who solves every step from its next run: another agent, or the pipeline again
sign    -       read the reply, change it, and sign it: then it leaves
inbox   -       the mail it watches: read a conversation, reply to it, archive it
cal     -       the calendar it watches: the week ahead, and invites to answer
roadmap -       the project it watches: what needs you, and issues to make tasks of'

# the board's keys besides the actions', and a form's (new, stack and say on the board, and t compose).
# Every key is here once: t ui binds it from here, and what the screens say about it comes from here.
BOARD_KEYS='new      ctrl-n  a new task
clean    ctrl-g  delete every task done, answered or held for 12 hours
keys     ?       every action, in the pane'
FORM_KEYS='details  ctrl-o  the details, in $EDITOR
repo     ctrl-r  another repo
pipeline ctrl-p  the pipelines, to pick one'
# t inbox's keys, on a screen of its own; ? lists them in its pane
INBOX_KEYS='open     enter   the thread, the width of the screen, with a reply or a comment typed under it
archive  ctrl-x  archive it, where the mail lives
keys     ?       every key, in the pane; again: the thread'
# t thread's: typing is fzf's query, so the keys are ctrl- ones, and ? and every letter are text
THREAD_KEYS='line     enter   a new line; backspace on an empty one takes the line above back
done     ctrl-d  end it: it holds on the board, and nothing leaves yet
comment  ctrl-t  a comment for your teammates instead, or a reply again; what you wrote comes along
draft    ctrl-s  an agent writes it, from what you wrote so far; again: writes it again
release  ctrl-y  sign what you ended: it leaves
edit     ctrl-e  write on at the end of what you ended
discard  ctrl-x  delete what you ended'
# t cal's: answering is the signature, so each answer is a key of its own
CAL_KEYS='open     enter   open it in the browser
accept   ctrl-y  accept the invite; the organizer is told
maybe    ctrl-t  answer maybe
decline  ctrl-x  decline it'
# t roadmap's: a status says what is already true, so the one it sets waits for no signature; ? lists them in its pane
ROADMAP_KEYS='open     enter   its sub-issues, as a list of their own
task     ctrl-t  a task of it: your note, then its pipeline, agent and repo; the issue goes to In progress, assigned to you
issue    ctrl-n  a new issue on the project: its title; in a list of sub-issues, a sub-issue of theirs
status   ctrl-s  move it on the project: the list turns into its statuses, and enter picks one
drop     ctrl-x  not mine: off this list, and nothing changes on GitHub
keys     ?       every key, in the pane; again: the issue'

# the key for $1 as fzf binds it (key_of agent → ctrl-s), and as the screens write it (key agent → ^s)
key_of() { printf '%s\n' "$ACTIONS" "$BOARD_KEYS" "$FORM_KEYS" "$INBOX_KEYS" "$THREAD_KEYS" "$CAL_KEYS" "$ROADMAP_KEYS" | awk -v n="$1" '$1 == n { print $2; exit }'; }
key() { keyname "$(key_of "$1")"; }

# how t ui writes a key: ctrl-l as ^l, and a key an action hasn't (-) as nothing
keyname() { if [ "$1" != - ]; then echo "${1/#ctrl-/^}"; fi; }

# keys and what they do, for a screen's bottom line: hint enter create esc back → "enter:create   esc:back"
hint() {
  local out=
  while [ $# -ge 2 ]; do out+="$1:$2   "; shift 2; done
  printf %s "${out%   }"
}

# fzf reads a newline in a paste as enter, which would end a form at the paste's first line. So enter in a form puts
# a space, and a moment later runs $1 with $FZF_QUERY as it is by then: still what enter left, and it was enter;
# else the paste went on, and the space keeps its lines apart.
after_paste() { echo "put( )+bg-transform~sleep 0.1; echo 'transform:$1'~"; }

# the reply task on conversation $2 in source $1 that hasn't left yet, if there is one
reply_to() {
  local found
  for found in $(grep -lx "conversation: $1 $2" /dev/null "$T_TASKS"/*/task.md 2> /dev/null || true); do
    found=${found%/task.md}
    if [ "$(cat "$found/pipeline")" = reply ] && [ "$(cat "$found/step")" != done ]; then echo "$found"; return; fi
  done
}

# the actions worth offering for a task now; Enter does the first. A watch offers its mail, and a reply
# held for your signature the signing.
offers() {
  case $(state "$1") in
    running) echo log diff cancel hold rm ;;
    ready)   if [ -f "$1/inbox" ]; then echo inbox log
             elif [ -f "$1/calendar" ]; then echo cal log
             elif [ -f "$1/roadmap" ]; then echo roadmap log
             elif [ -s "$1/log/$(cat "$1/step").log" ]; then echo log run hold
             else echo run hold rm; fi ;;
    after*)  echo log rm ;;
    HOLD)    if [[ $(cat "$1/step") == *-sign ]]; then echo sign say rm; else echo say log attach hold; fi ;;
    *)       if [ -f "$1/answer.md" ]; then echo say stack rm; else echo diff stack say rm; fi ;;
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

# the files task $1 changed, a line each, tab-separated: +12 -3, the path, and "generated" for what
# tooling writes (GENERATED= in its env)
changed_files() {
  local - generated added deleted file mark glob
  set -f                                      # a GENERATED glob matches the change's paths, not files here
  generated=$(load_env "$1" > /dev/null 2>&1; echo "${GENERATED:-}")
  CLICOLOR_FORCE= t-diff "$1" --numstat --no-renames | while IFS=$'\t' read -r added deleted file; do
    mark=
    for glob in $generated; do
      if [[ $file == $glob ]]; then mark=generated; fi
    done
    if [ "$added" = - ]; then added=binary; else added="+$added -$deleted"; fi
    printf '%s%12s%s\t%s\t%s\n' "$C_DIM" "$added" "$C_OFF" "$file" "${mark:+$C_FAINT$mark$C_OFF}"
  done
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
