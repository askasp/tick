# lib/corpus.sh — mail you wrote before, for an agent drafting a reply the way you write. Sourced by steps/draft.
# jobs/mail-corpus keeps it: $T_VAR/corpus/SOURCE/ID.md, headers (to:, subject:, date:), a blank line, the text,
# and the file's mtime is when it was sent.

# the files in $1 sent to an address matching $2, newest first
mail_to() {
  grep -il "^to: .*$(sed 's/[][\.*^$]/\\&/g' <<< "$2")" "$1"/*.md 2> /dev/null | xargs -r ls -t | sed -n '1,50p'
}

# what you wrote in source $1: to $2 first, then to anyone at its domain, then the newest, as many as CORPUS_MAX
# bytes hold, each after a --- line
corpus_examples() {
  local dir=$T_VAR/corpus/$1 address=${2:-} file used=0 size seen=" "
  [ -d "$dir" ] || return 0
  while read -r file; do
    if [[ $seen == *" $file "* ]]; then continue; fi
    seen+="$file "
    size=$(wc -c < "$file")
    if [ $((used + size)) -gt "$CORPUS_MAX" ]; then continue; fi
    used=$((used + size))
    printf '\n---\n'
    cat "$file"
  done < <(
    if [ -n "$address" ]; then
      mail_to "$dir" "$address"
      mail_to "$dir" "@${address#*@}"
    fi
    ls -t "$dir"/*.md 2> /dev/null | sed -n '1,50p')
}
