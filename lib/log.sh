# lib/log.sh — how t log reads a task's logs: every run in the order it ran (story), a run of one
# tool folded into a line (digest), and the layout the pane and the terminal show (render).

# mawk reads ahead a block at a time, so a line tail -F follows would sit in render waiting for
# the ones after it. Every other awk hands a line on as it comes.
T_AWK_LIVE=()
if awk -W version 2>&1 | grep -qi mawk; then T_AWK_LIVE=(-Winteractive); fi

# Each step logs its runs ("=== DATE TIME step, run N") apart, and times are to the second, so
# history, which says in order how each run ended, decides whose run comes next. A run that had
# to wait (exit 75) keeps its number, so it goes out together with the run after it.
story() {
  local f have=()
  for f in "${files[@]}"; do
    if [ -f "$f" ]; then have+=("$f"); fi
  done
  if [ ${#have[@]} -eq 0 ]; then return 0; fi
  awk 'function pending(s) { return p[s] < n[s] }
       function start(s)   { return at[s, p[s] + 1] }
       function emit(s)    { p[s]++; printf "%s", run[s, p[s]] }
       function before(when, or_at,  s, b) {    # every run started before `when`, oldest first
         for (;;) {
           b = ""
           for (s in n) if (pending(s) && (start(s) < when || (or_at && start(s) == when)) && (b == "" || start(s) < start(b))) b = s
           if (b == "") return
           emit(b)
         }
       }
       FILENAME != "history" {
         if (FNR == 1) { s = FILENAME; n[s] = 0 }
         if (/^=== [0-9-]+ [0-9:]+ /) { n[s]++; at[s, n[s]] = $2 " " $3; num[s, n[s]] = $NF }
         else if (!n[s]) { n[s] = 1; at[s, 1] = "" }
         run[s, n[s]] = run[s, n[s]] $0 "\n"
         next
       }
       { s = "log/" $4 ".log"
         if ((s in n) && pending(s)) {
           before(start(s)); emit(s)
           while (pending(s) && num[s, p[s] + 1] == num[s, p[s]] && start(s) <= $1 " " $2) emit(s)
         } else before($1 " " $2, 1)
         print }
       END { before("~", 1) }' "${have[@]}"
}

# three or more calls of one tool in a row become one line: "· Read ×8  src/lib/health-*, src/app.ts".
# While the task runs, its last three calls stay lines of their own, so the log still moves.
digest() {
  local live=
  if [ "$(state "$task")" = running ]; then live=1; fi
  awk -v live="$live" '
    function common(a, b) {
      while (a != "" && index(b, a) != 1) a = substr(a, 1, length(a) - 1)
      return a
    }
    # the calls folded: paths by directory, with what their names start with; commands by their first word
    function summary(k,   i, a, j, g, ng, out, seen, order, first, pre, many) {
      for (i = 1; i <= k; i++) {
        a = arg[i]
        sub(/ .*/, "", a)
        j = arg[i] ~ / / ? 1 : match(a, /[^\/]*$/)
        g = j > 1 ? substr(a, 1, j - 1) : a
        if (!(g in seen)) { seen[g] = 1; order[++ng] = g; first[g] = a; pre[g] = substr(a, j) }
        else if (a != first[g]) { many[g] = 1; pre[g] = common(pre[g], substr(a, j)) }
      }
      for (i = 1; i <= ng && i <= 6; i++) {
        g = order[i]
        out = out (i > 1 ? ", " : "") (many[g] ? g pre[g] "*" : first[g])
      }
      return out (ng > 6 ? ", …" : "")
    }
    function flush(keep,   i, k) {
      k = n - keep >= 3 ? n - keep : 0
      if (k) print "  · " tool " ×" k "  " summary(k)
      for (i = k + 1; i <= n; i++) print line[i]
      n = 0
    }
    /^  · / {
      if ($2 != tool) flush(0)
      tool = $2
      line[++n] = $0
      arg[n] = substr($0, index($0, $2) + length($2) + 1)
      next
    }
    { flush(0); print }
    END { flush(live ? 3 : 0) }'
}

# how wide the text may be: the pane's width, else the screen it is drawn on. Piped somewhere it is
# 0, and then nothing folds: whoever reads it decides.
width() {
  local cols=${FZF_PREVIEW_COLUMNS:-0}
  if [ "$cols" = 0 ] && [ -t 1 ]; then read -r _ cols < <(stty size < /dev/tty 2> /dev/null) || cols=0; fi
  echo "${cols:-0}"
}

# One text column, seven in, with the time in the gutter where a run tells us one. A run's banner
# says which step it came from and its run number, so the "ok → next" line before it is dropped;
# what that line says when it isn't plain ok — failed, cancelled, held, done — stays, in red.
# The agent writes markdown for a renderer that isn't there, so this is the renderer: ## bright,
# ** strong, `code` red, - a bullet, and the characters themselves go. Long lines fold on words,
# because a word broken in half is the worst thing on the screen.
render() {
  if [ -z "$C_OFF" ] || [ -n "${NO_COLOR:-}" ]; then local C_BRIGHT= C_TEXT= C_DIM= C_FAINT= C_RED= C_OFF=; fi
  awk "${T_AWK_LIVE[@]}" -v cols="$cols" -v bright="$C_BRIGHT" -v text="$C_TEXT" -v dim="$C_DIM" \
      -v faint="$C_FAINT" -v red="$C_RED" -v off="$C_OFF" '
    function say(s) {                      # the gutter carries the time once, on the first line
      print (at ? faint substr(at, 1, 5) off "  " : "       ") s
      at = ""
      fflush()
    }
    function vlen(s) { gsub(/[\001\002\003]/, "", s); return length(s) }
    function paint(s) { gsub(/\001/, bright, s); gsub(/\003/, red, s); gsub(/\002/, text, s); return s }
    function edge(left, right,   room) {   # right at the right edge of the pane, or just along
      room = (cols > 40 ? cols : 60) - 8 - length(left) - length(right)
      return sprintf("%*s", room > 2 ? room : 2, "")
    }
    function fold(s, ind,   i, n, w, line, words) {
      n = split(s, words, " ")
      for (i = 1; i <= n; i++) {
        w = words[i]
        if (line == "") line = w
        else if (cols > 20 && vlen(line) + vlen(w) + 8 + length(ind) >= cols) { say(text ind paint(line) off); line = w }
        else line = line " " w
      }
      if (line != "") say(text ind paint(line) off)
    }
    function toggle(s, mark, on, from,   out, p, open) {
      while ((p = index(s, mark)) > 0) {
        out = out substr(s, 1, p - 1) (open ? "\002" : on)
        s = substr(s, p + length(mark))
        open = !open
      }
      return out s (open ? "\002" : "")
    }
    function verb(v) {
      v = tolower(v)
      if (v == "bash") return "sh"
      if (v ~ /edit$/ || v == "patch") return "edit"
      if (v ~ /^web/) return "web"
      if (v ~ /^todo/) return "todo"
      return v
    }
    { gsub(/\033\[[0-9;]*m/, "") }
    /^session: / { next }
    /^=== [0-9-]+ [0-9:]+ / {
      at = $3
      step = $4; sub(/,$/, "", step); sub(/^[0-9]+-/, "", step)
      came = (prev && prev != step) ? prev " → " step : step
      prev = step
      say(text came off edge(came, "run " $NF) dim "run " $NF off)
      next
    }
    /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] / {
      at = $2
      rest = $0
      sub(/^[^ ]+ [^ ]+ [^ ]+ /, "", rest)      # the date, the time, the task number
      sub(/^[0-9]+-/, "", rest); sub(/→ [0-9]+-/, "→ ", rest)
      if (rest ~ / ok → /) {
        if (rest ~ /→ done$/) { sub(/ ok → /, " → ", rest); say(text rest off) } else at = ""
      } else say(red rest off)
      next
    }
    /^ *! / { sub(/^ *! */, ""); say(red "! " $0 off); next }
    /^  · / {
      args = $0; sub(/^  · [^ ]+ */, "", args)
      call = sprintf("%-6s %s", verb($2), args)
      if (cols > 20 && length(call) + 8 >= cols) call = substr(call, 1, cols - 9) "…"
      say(dim call off)
      next
    }
    /^HOLD: / { say(red $0 off); next }
    /^ *$/ { print ""; fflush(); next }
    {
      match($0, /^ */); ind = substr($0, 1, RLENGTH); body = substr($0, RLENGTH + 1)
      if (sub(/^#+ +/, "", body)) body = "\001" body "\002"
      else {
        sub(/^[-*] +/, "· ", body)
        body = toggle(toggle(body, "**", "\001"), "`", "\003")
      }
      fold(body, ind)
    }'
}
