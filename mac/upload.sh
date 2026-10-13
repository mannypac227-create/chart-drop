#!/bin/bash
# Chart Drop uploader: sends new screenshots from two Dropbox folders on this Mac
# to the public GitHub repo mannypac227-create/chart-drop, each in its own lane:
#   ~/Dropbox/Charts    -> shots/      (read by the Hourly Forex & Gold Brief)
#   ~/Dropbox/Wholesale -> wholesale/  (read by the Wholesale Property Reader)
# Nothing else is uploaded. Old uploads are deleted from GitHub automatically
# (charts after yesterday, wholesale screenshots after 7 days).
# Runs in the background (launchd) whenever a chart lands, and every 5 minutes.
set -u

REPO="mannypac227-create/chart-drop"
BRANCH="main"
DIR="$HOME/.chart-drop"
STATE="$DIR/uploaded.txt"
LOG="$DIR/upload.log"
WATCH=("$HOME/Dropbox/Charts" "$HOME/Dropbox/Wholesale")
lane_of() { case "$(basename "$1")" in Wholesale) echo wholesale;; *) echo shots;; esac; }
MAX_AGE_MIN=1440   # catch up on anything from the last 24 hours

mkdir -p "$DIR"
touch "$STATE"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

# One run at a time.
LOCK="$DIR/lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

TOKEN=$(security find-generic-password -s chart-drop -a github -w 2>/dev/null) || {
  log "No GitHub key saved in Keychain. Run the installer again."
  exit 1
}
api() { curl -sS --max-time 120 -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
             -H "X-GitHub-Api-Version: 2022-11-28" "$@"; }

sleep 3   # give a just-taken screenshot time to finish writing

# 1. Upload new charts.
for d in "${WATCH[@]}"; do
  [ -d "$d" ] || continue
  src=$(basename "$d" | tr 'A-Z ' 'a-z-')
  lane=$(lane_of "$d")
  find "$d" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
       -mmin "-$MAX_AGE_MIN" -print0 2>>"$LOG" |
  while IFS= read -r -d '' f; do
    mt=$(stat -f %m "$f" 2>/dev/null) || continue
    key="$f|$mt"
    grep -qxF "$key" "$STATE" && continue

    ext=$(echo "${f##*.}" | tr 'A-Z' 'a-z')
    day=$(TZ=America/New_York date -r "$mt" +%Y-%m-%d)
    stamp=$(TZ=America/New_York date -r "$mt" +%H-%M-%S)
    sum=$(md5 -q "$f" | cut -c1-8)
    path="$lane/$day/${day}_${stamp}_${src}_${sum}.${ext}"

    body=$(mktemp "$DIR/body.XXXXXX")
    {
      printf '{"message":"Add %s","branch":"%s","content":"' "$path" "$BRANCH"
      base64 -i "$f" | tr -d '\n'
      printf '"}'
    } > "$body"
    code=$(api -o "$DIR/last-response.json" -w '%{http_code}' -X PUT --data-binary @"$body" \
      "https://api.github.com/repos/$REPO/contents/$path" 2>>"$LOG")
    rm -f "$body"

    # 201 created; 422 means that exact file is already there.
    if [ "$code" = "201" ] || [ "$code" = "200" ] || [ "$code" = "422" ]; then
      echo "$key" >> "$STATE"
      log "Uploaded $(basename "$f") -> $path (HTTP $code)"
    else
      log "Upload failed for $(basename "$f"): HTTP $code, will retry"
    fi
  done
done

# 2. Twice a day, delete old uploads from GitHub (charts: older than yesterday;
#    wholesale: older than 7 days).
cleanup() {
  local lane="$1" keep="$2"
  api "https://api.github.com/repos/$REPO/contents/$lane?ref=$BRANCH" 2>>"$LOG" |
    grep -o '"name": *"[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}"' | grep -o '[0-9]\{4\}-[0-9-]*' |
  while read -r day; do
    [[ "$day" < "$keep" ]] || continue
    list=$(mktemp "$DIR/list.XXXXXX")
    api "https://api.github.com/repos/$REPO/contents/$lane/$day?ref=$BRANCH" > "$list" 2>>"$LOG"
    paste -d' ' <(grep -o '"path": *"[^"]*"' "$list" | sed 's/.*: *"//; s/"$//') \
                <(grep -o '"sha": *"[^"]*"' "$list" | sed 's/.*: *"//; s/"$//') |
    while read -r p sha; do
      [ -n "$p" ] && [ -n "$sha" ] || continue
      code=$(api -o /dev/null -w '%{http_code}' -X DELETE \
        --data "{\"message\":\"Remove old $p\",\"sha\":\"$sha\",\"branch\":\"$BRANCH\"}" \
        "https://api.github.com/repos/$REPO/contents/$p" 2>>"$LOG")
      log "Cleanup: removed $p (HTTP $code)"
    done
    rm -f "$list"
  done
}
STAMP="$DIR/last-cleanup"
if [ ! -f "$STAMP" ] || [ -n "$(find "$STAMP" -mmin +720 2>/dev/null)" ]; then
  touch "$STAMP"
  cleanup shots "$(TZ=America/New_York date -v-1d +%Y-%m-%d)"
  cleanup wholesale "$(TZ=America/New_York date -v-7d +%Y-%m-%d)"
fi
