# jobs/slack.sh — what jobs/slack-out and jobs/slack-in share: the token, which channel belongs to
# which repo, and one Slack call. Sourced by both, never run.
#
# ~/.config/slack/env holds, and nothing else does:
#   SLACK_TOKEN=xoxb-…              a bot token: chat:write, channels:history, reactions:write, pins:write
#   SLACK_CHANNELS="C0AMINO=amino"  CHANNEL=repo, a pair for each repo in repos/ you want on Slack
#   SLACK_ME=U0AKSEL               who a held task mentions
#
# Nothing else in tick reads a line either script writes, so `rm jobs/slack*`, the two crontab lines
# and $T_VAR/slack leave tick exactly as it was.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/tick.sh"
set -euo pipefail

slack_conf=${XDG_CONFIG_HOME:-$HOME/.config}/slack/env
[ -r "$slack_conf" ] ||
  die "no $slack_conf; write SLACK_TOKEN=xoxb-… and SLACK_CHANNELS=\"C0123=amino\" into it, then: chmod 600 $slack_conf"
. "$slack_conf"
[ -n "${SLACK_TOKEN:-}" ] || die "no SLACK_TOKEN in $slack_conf"
SLACK_STATE=$T_VAR/slack
mkdir -p "$SLACK_STATE"

# one Slack call: api METHOD field=value … . The answer goes to stdout. An error Slack names itself
# (already_reacted, message_not_found) goes to stderr and returns 1, so the caller can go on to the
# next task; only a refused token stops the job.
api() {
  local method=$1 fields=() f out
  shift
  for f; do fields+=(--data-urlencode "$f"); done
  out=$(curl -sfS --retry 3 -H "Authorization: Bearer $SLACK_TOKEN" "${fields[@]}" "https://slack.com/api/$method") ||
    die "slack refused $method; check SLACK_TOKEN in $slack_conf"
  if [ "$(jq -r .ok <<< "$out")" != true ]; then
    echo "slack: $method: $(jq -r '.error // "?"' <<< "$out")" >&2
    return 1
  fi
  printf '%s' "$out"
}

# the channel bound to a task's repo; a task whose repo has none stays out of Slack
channel_of() {
  local repo pair
  repo=$(profile_of "$(cat "$1/repo" 2> /dev/null)")
  [ -n "$repo" ] || return 1
  for pair in ${SLACK_CHANNELS:-}; do
    if [ "${pair#*=}" = "$repo" ]; then echo "${pair%%=*}"; return; fi
  done
  return 1
}

# where a task is, in the board's own words: 3/4 · 3m · review  read client.ts
where() {
  local since
  since=$(age "$1")
  echo "$(fraction "$1")${since:+ · $since} · $(status "$1")"
}

put() { printf '%s\n' "$2" > "$1.tmp" && mv "$1.tmp" "$1"; }
get() { cat "$1" 2> /dev/null || true; }
