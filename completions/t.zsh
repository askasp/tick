# completions/t.zsh — tab completion for t in zsh. In ~/.zshrc, after compinit:
#   source ~/git/tick/completions/t.zsh
# The candidates come from `t complete`, so they are always what is on disk right now.

_t_complete() { reply=(${(f)"$(command t complete "$@" 2> /dev/null)"}) }

_t() {
  local -a reply new=('-p:pipeline' '-r:repo: a name or a path' '--on:stack it on a task'
    '--cli:claude or opencode' '--test:the test command' '--base:the branch to start from'
    '--now:run it here, now' '-:read the details from stdin')
  if (( CURRENT == 2 )); then
    _t_complete commands; _describe command reply; return
  fi
  case $words[CURRENT-1] in
    -p)    _t_complete pipelines; _describe pipeline reply; return ;;
    -r)    _t_complete repos; _describe repo reply; _files -/; return ;;
    --cli) _t_complete clis; _describe cli reply; return ;;
    --on)  _t_complete tasks; _describe task reply; return ;;
  esac
  case $words[2] in
    new) reply=($new); _describe option reply ;;
    show|log|diff|say|sign|attach|run|hold|resume|name|path|rm)
      if (( CURRENT == 3 )); then
        _t_complete tasks; _describe task reply
      elif [[ $words[2] == resume ]] && (( CURRENT == 4 )); then
        _t_complete steps $words[3]; _describe step reply
      elif [[ $words[2] == log ]]; then
        reply=('-f:follow it live'); _describe option reply
      fi ;;
    ls) reply=('-a:done tasks too'); _describe option reply ;;
    *)                                          # t PIPELINE is t new -p PIPELINE
      _t_complete pipelines
      if (( ${reply[(I)$words[2]:*]} )); then reply=($new); _describe option reply; fi ;;
  esac
}

compdef _t t
