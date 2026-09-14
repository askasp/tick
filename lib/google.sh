# lib/google.sh — a Google account: its login, and calls to its APIs. Sourced by sources/gmail, calendars/gcal and t google.
# ~/.config/google/NAME/env holds GOOGLE_CLIENT_ID= and GOOGLE_CLIENT_SECRET= (a Desktop app's OAuth client), and
# refresh_token beside it is what `t google login NAME` wrote. Each account has a directory of its own.

google_dir() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/google/$1"; }

# account $1's OAuth client, into GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET
google_client() {
  local dir
  dir=$(google_dir "$1")
  [ -r "$dir/env" ] || die "no $dir/env; make a Desktop app OAuth client in Google Cloud, write GOOGLE_CLIENT_ID=... and GOOGLE_CLIENT_SECRET=... into it, chmod 600 it, then: t google login $1"
  . "$dir/env"
}

# account $1, logged in for the calls that follow: a fresh access token into GOOGLE_TOKEN
google_account() {
  local dir
  dir=$(google_dir "$1")
  google_client "$1"
  [ -s "$dir/refresh_token" ] || die "google account $1 is not logged in; log in with: t google login $1"
  GOOGLE_ACCOUNT=$1
  GOOGLE_TOKEN=$(jq -rn --arg id "$GOOGLE_CLIENT_ID" --arg secret "$GOOGLE_CLIENT_SECRET" --rawfile refresh "$dir/refresh_token" \
      '"client_id=\($id | @uri)&client_secret=\($secret | @uri)&refresh_token=\($refresh | rtrimstr("\n") | @uri)&grant_type=refresh_token"' |
    curl -sfS --retry 3 --data-binary @- https://oauth2.googleapis.com/token | jq -r '.access_token // empty') || true
  [ -n "$GOOGLE_TOKEN" ] || die "Google refused account $1's login; log in again with: t google login $1"
}

# one call: METHOD URL, with a JSON body on stdin for anything but GET. Only a GET is retried: a POST that
# timed out may still have sent its mail.
google() {
  local how=(--retry 5)
  if [ "$1" != GET ]; then how=(-X "$1" -H 'Content-Type: application/json' --data-binary @-); fi
  curl -sfS "${how[@]}" -H "Authorization: Bearer $GOOGLE_TOKEN" "$2" ||
    die "Google refused $1 ${2%%\?*}; if account $GOOGLE_ACCOUNT's login lapsed: t google login $GOOGLE_ACCOUNT"
}

uri() { jq -rn --arg s "$1" '$s | @uri'; }
