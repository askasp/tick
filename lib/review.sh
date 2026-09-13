# lib/review.sh — the prompt a reviewer reads, and one pass over it. steps/review reads a task it is
# standing in; jobs/idle-review reads finished ones from outside. Every function takes the task's
# directory. The caller loads the task's settings first (GENERATED, DIFF_MAX, MINDSETS):
#   set -a; load_env "$task"; set +a
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tick.sh"

# what tooling writes (GENERATED= in the repo's env) is no one's work to review, and it is huge
review_diff() {
  local task=$1 glob skip=(.)
  shift
  for glob in ${GENERATED:-}; do skip+=(":(exclude)$glob"); done
  git -C "$task/work" diff "$(cat "$task/base")...HEAD" "$@" -- "${skip[@]}"
}

# a whole diff can be bigger than the model's context: whole file patches, smallest first, until
# DIFF_MAX bytes are spent. The files left out are named, and the reviewer reads those itself.
review_patches() {
  local task=$1 left=$DIFF_MAX size file left_out=()
  while read -r size file; do
    if [ "$size" -gt "$left" ]; then left_out+=("$file"); continue; fi
    left=$((left - size))
    printf '```diff\n'; review_diff "$task" -- "$file"; printf '```\n\n'
  done < <(review_diff "$task" --name-only | while IFS= read -r file; do
             echo "$(review_diff "$task" -- "$file" | wc -c) $file"
           done | sort -n)
  if [ "${#left_out[@]}" -gt 0 ]; then
    printf 'Too large for this prompt; read these files in the worktree yourself:\n'
    printf -- '- %s\n' "${left_out[@]}"
  fi
}

review_prompt() {
  local task=$1
  cat "$task/task.md"
  printf '\n## The change (git diff %s...HEAD)\n\n```\n' "$(cat "$task/base")"
  review_diff "$task" --stat
  printf '```\n\n'
  review_patches "$task"
}

# mindsets/NAME.md, or nothing said and a failure naming the ones there are
mindset_file() {
  local file=$T_ROOT/mindsets/$1.md
  [ -f "$file" ] || die "no mindset '$1'; there are: $(ls "$T_ROOT/mindsets" | sed 's/\.md$//' | xargs)"
  echo "$file"
}

# one review of task $1 with mindset $2 (empty: the whole diff at once), its text on stdout.
# $3, when it exists, is what this pass asked for last round: the fix is judged against it.
review_pass() {
  { review_prompt "$1"
    if [ -n "${2:-}" ]; then printf '\n## This review\n\n'; cat "$(mindset_file "$2")"; fi
    if [ -f "${3:-}" ]; then
      printf '\n## What you asked for last round\n\n'
      cat "$3"
      printf '\nThe change above tried to fix that. Ask for changes again only for what is still not done,'
      printf ' or for a bug the fix itself added. Anything new you notice is a note: approve.\n'
    fi
  } | (cd -P "$1/work" && agent reviewer)
}

verdict_of() { grep -oE '^VERDICT: *(approve|changes)' <<< "$1" | tail -1; }
