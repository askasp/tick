# lib/thread.sh — what t thread draws: the conversation, what you write where it will land, and who will read it.
# Sourced by bin/t-thread, which keeps the screen in $here: conv (SOURCE ID), kind (reply or comment), at (the message a
# reply goes under, where the source has threads), mode (write, drafting, held, signed), task, and text.

kept() { cat "$here/$1" 2> /dev/null || true; }
keep() { printf '%s\n' "$2" > "$here/$1.tmp" && mv "$here/$1.tmp" "$here/$1"; }
lines() { wc -l < "$here/text"; }
written() { grep -qs '[^[:space:]]' "$here/text"; }

inbox() { local name; read -r name _ <<< "$(kept conv)"; echo "$name"; }
conv_id() { local id; read -r _ id <<< "$(kept conv)"; echo "$id"; }
can() { "$T_ROOT/sources/$(inbox)" can "$1" > /dev/null 2>&1; }
mail() { echo "$T_VAR/mail/$(inbox)/$(conv_id)"; }
thread_md() { if [ -f "$(mail)/thread.md" ]; then echo "$(mail)/thread.md"; else echo "$(kept task)/thread.md"; fi; }
subject() { sed -n '1s/^# //p' "$(thread_md)" 2> /dev/null | grep . || echo "(no subject)"; }
conv_field() { jq -r ".$1 // empty" "$(mail)/conv.json" 2> /dev/null || true; }
positions() { sed -n 's/^<!-- ts \(.*\) -->$/\1/p' "$(thread_md)" 2> /dev/null || true; }

# where what you write goes, as task.md's conversation line says it: SOURCE ID, and /TS into the thread under message TS
target() { if [ "$(kept kind)" = reply ] && [ -n "$(kept at)" ]; then echo "$(kept conv)/$(kept at)"; else kept conv; fi; }

# its pipeline: comment, or the one a reply in this source goes through (slack-reply, or reply)
pipeline_for() { if [ "$(kept kind)" = comment ]; then echo comment; else reply_pipeline "$(inbox)"; fi; }

# the prompt a line is typed at, with $1 lines above it: > at the end, └ under a message or as a comment, then in line
prompt() {
  if [ "${1:-$(lines)}" -gt 0 ]; then echo "  "
  elif [ "$(kept kind)" = comment ] || [ -n "$(kept at)" ]; then echo "└ "
  else echo "> "; fi
}

yours() { case $(kept mode) in held) echo unsigned ;; signed) echo signed ;; *) echo now ;; esac; }

# the last message the task's thread had when you wrote it, and how many came after it
wrote_after() { sed -n 's/^<!-- ts \(.*\) -->$/\1/p' "$(kept task)/thread.md" 2> /dev/null | tail -1; }
since() {
  local last
  last=$(wrote_after)
  if [ -z "$(kept task)" ] || [ -z "$last" ]; then echo 0; return; fi
  positions | awk -v last="$last" '($1 "") > (last "")' | wc -l
}

# the thread as thread_view takes it, with what you write where it lands: into the thread under message $at, as a
# comment at the end, or once ended as your message at the end; and a rule before what was said since you wrote it
view_md() {
  local place= since=0 last=
  if [ -n "$(kept task)" ]; then last=$(wrote_after) since=$(since); fi
  if [ "$(kept kind)" = comment ]; then place=END; printf '### └ comment by you, %s\n\n' "$(yours)" > "$here/block"
  elif [ -n "$(kept at)" ]; then place=$(kept at); printf '### └ reply by you, %s\n\n' "$(yours)" > "$here/block"
  elif [ "$(kept mode)" != write ] && [ -s "$here/text" ]; then place=END; printf '## message from you, %s\n\n' "$(yours)" > "$here/block"
  fi
  if [ -n "$place" ]; then cat "$here/text" >> "$here/block"; fi
  awk -v place="$place" -v last="$last" -v since="$since" -v block="$here/block" '
    function put(  line) { while ((getline line < block) > 0) print line; close(block); pending = 0 }
    held != "" && /^<!-- ts / {
      if (last != "" && !ruled && ($3 "") > (last "")) {
        print "_── " since (since == 1 ? " message" : " messages") " since you wrote yours_"; print ""; ruled = 1
      }
      print held; held = ""; print
      if ($3 == place) pending = 1
      next
    }
    held != "" { print held; held = "" }
    /^## / { if (pending) put(); held = $0; next }
    { print }
    END { if (held != "") print held; if (pending || place == "END") put() }' "$(thread_md)"
}

delivery() {
  if [ "$(env_get "$T_ROOT/pipelines/$(pipeline_for)/env" DELIVER)" = send ]; then echo "sent as you once signed"
  else echo "a draft in $(inbox) once signed"; fi
}

# who wrote the message the prompt is under, and when: Marius Lie 13:41
message_at() {
  awk -v at="$(kept at)" '
    /^## / { who = substr($0, 4); sub(/^[^ ]* from /, "", who) }
    $0 == "<!-- ts " at " -->" { n = split(who, part, ", "); when = part[n]; sub(/.* /, "", when); sub(/, [^,]*$/, "", who); print who " " when; exit }' "$(thread_md)"
}

# who reads it, over where you type. The red is the wider audience, in every source: a reply to the customer, not the
# comment; a message to the channel, not the thread.
signature() {
  local n= what since= subject members from
  subject=$(subject) from=$(conv_field from)
  if [ -n "$(kept task)" ]; then
    n="task $(task_num "$(kept task)") · "
    if [ "$(since)" -gt 0 ]; then since=" · $(since) said since you wrote it"; fi
  fi
  if [ "$(kept kind)" = comment ]; then
    what="${C_TEXT}comment$C_OFF  ${C_MID}internal, for your teammates$C_OFF$C_DIM${from:+ · $from cannot see it}$C_OFF"
  elif [ -n "$(kept at)" ]; then
    what="${C_TEXT}thread$C_OFF  ${C_MID}under $(message_at)$C_OFF$C_DIM · anyone in $subject can open it, nobody is pinged$C_OFF"
  elif can threads && [[ $subject != \#* ]]; then
    what="${C_TEXT}dm$C_OFF  ${C_MID}to $subject$C_OFF$C_DIM · only they see it$C_OFF"
  elif can threads; then
    members=$(conv_field meta)
    what="${C_RED}channel$C_OFF  ${C_MID}$subject${members:+ · ${members%% ·*}}$C_OFF$C_DIM · they see it at once, in the channel$C_OFF"
  else
    what="${C_RED}reply$C_OFF  $C_MID${from:+to $from}$C_OFF$C_DIM · $(delivery)$C_OFF"
  fi
  case $(kept mode) in
    write)    echo "$what" ;;
    drafting) echo "$what"; echo "$C_DIM       ${n}an agent writes it, and it appears here for you to change$C_OFF" ;;
    held)     echo "${C_RED}held$C_OFF  $what"; echo "$C_DIM       ${n}nothing has left$since: $(key release) sends it$C_OFF" ;;
    signed)   echo "${C_MID}sent$C_OFF  $what"; echo "$C_DIM       ${n}it has left$C_OFF" ;;
  esac
}

pane() {
  local rule note
  rule=$C_FAINT$(printf '%*s' "${FZF_PREVIEW_COLUMNS:-80}" '' | sed 's/ /─/g')$C_OFF
  note=$(conv_field meta)
  echo "$C_DIM$(inbox)$C_OFF  $C_BRIGHT$(subject)$C_OFF  $C_FAINT${note:-$(conv_field from)}$C_OFF"
  echo "$rule"
  if [ -s "$(mail)/gist" ]; then                        # what you triaged by stays on top of what it sums up
    fold -s -w "${FZF_PREVIEW_COLUMNS:-80}" "$(mail)/gist" | sed "s/^/$C_DIM/; s/\$/$C_OFF/"
    echo "$rule"
  fi
  if [ -f "$(thread_md)" ]; then view_md | thread_view /dev/stdin; else echo "${C_DIM}no thread read yet$C_OFF"; fi
  echo
  echo "$rule"
  signature
  if [ -e "$here/drafted" ]; then echo "$C_FAINT       drafted by an agent · read it before you sign$C_OFF"; fi
  if [ -s "$here/text" ] && [ "$(kept mode)" = write ] && [ "$(kept kind)" = reply ] && [ -z "$(kept at)" ]; then
    echo
    sed '1s/^/> /; 2,$s/^/  /' "$here/text"
  fi
}

# the pane's window: the header and the gist stay put, and the rest follows the end, or with $1 shows line $1 mid-pane
window() {
  local pinned=2
  if [ -s "$(mail)/gist" ]; then pinned=$((3 + $(fold -s -w "${FZF_COLUMNS:-80}" "$(mail)/gist" | wc -l))); fi
  if [ -n "${1:-}" ]; then echo "change-preview-window(nofollow,~$pinned,+$1-/2)"
  else echo "change-preview-window(follow,~$pinned)"; fi
}

# the line of the pane where your reply sits under its message
marker_line() {
  FZF_PREVIEW_COLUMNS=${FZF_COLUMNS:-80} pane | sed 's/\x1b\[[0-9;]*m//g' | grep -n '^  └ you  ' | tail -1 | cut -d: -f1
}

# the message above ($1 up) or below the one the prompt is under; below the last is the end, and up from there the last
moved() {
  local all i j
  mapfile -t all < <(positions)
  i=${#all[@]}
  for j in "${!all[@]}"; do if [ "${all[j]}" = "$(kept at)" ]; then i=$j; fi; done
  if [ "$1" = up ]; then i=$((i > 0 ? i - 1 : 0)); else i=$((i + 1)); fi
  if [ "$i" -lt "${#all[@]}" ]; then echo "${all[i]}"; fi
}

# the keys, on the line under the prompt: only what this source can do
footer() {
  local keys=()
  case $(kept mode) in
    write)
      keys=(enter "new line" "$(key release)" send)
      if can comment && [ "$(kept kind)" = comment ]; then keys+=("$(key comment)" "reply instead")
      elif can comment; then keys+=("$(key comment)" "comment instead"); fi
      keys+=("$(key draft)" "agent draft")
      if can threads; then keys+=("$(key up) $(key down)" message "$(key channel)" "to the channel"); else keys+=("$(key up) $(key down)" scroll); fi
      if can react; then keys+=("$(key react)" react); fi
      keys+=(esc back) ;;
    drafting) keys=(esc "back: it holds on the board once written") ;;
    held)
      keys=("$(key release)" sign "$(key edit)" edit "$(key draft)" redraft)
      if can react; then keys+=("$(key react)" "react instead"); fi
      keys+=("$(key discard)" discard esc "leave it held") ;;
    signed) keys=(esc back) ;;
  esac
  printf ' %s ' "$(hint "${keys[@]}")"
}
