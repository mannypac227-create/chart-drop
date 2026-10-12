#!/bin/bash
# Chart Drop uploader: sends new chart screenshots from Dropbox on this Mac
# to the private GitHub repo mannypac227-create/chart-drop, so the cloud
# hourly brief can read them even when this Mac is closed.
# Runs in the background (launchd) whenever a screenshot lands, and every 5 min.
set -u

REPO="mannypac227-create/chart-drop"
BRANCH="main"
DIR="$HOME/.chart-drop"
STATE="$DIR/uploaded.txt"
LOG="$DIR/upload.log"
WATCH=("$HOME/Dropbox/Screenshots" "$HOME/Dropbox/Charts")
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
# Screenshots are scrambled (AES-256) before upload, so the public repo only
# holds unreadable files. Only the hourly brief has this key.
SCRAMBLE=$(security find-generic-password -s chart-drop -a scramble -w 2>/dev/null) || {
  log "No scramble key saved in Keychain. Run the installer again."
  exit 1
}

sleep 3   # give a just-taken screenshot time to finish writing

for d in "${WATCH[@]}"; do
  [ -d "$d" ] || continue
  src=$(basename "$d" | tr 'A-Z ' 'a-z-')
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
    path="shots/$day/${day}_${stamp}_${src}_${sum}.${ext}.enc"

    enc=$(mktemp "$DIR/enc.XXXXXX")
    if ! openssl enc -aes-256-cbc -md sha256 -salt -in "$f" -out "$enc" -pass "pass:$SCRAMBLE" 2>>"$LOG"; then
      rm -f "$enc"; log "Could not scramble $(basename "$f"), will retry"; continue
    fi
    body=$(mktemp "$DIR/body.XXXXXX")
    {
      printf '{"message":"Add %s","branch":"%s","content":"' "$path" "$BRANCH"
      base64 -i "$enc" | tr -d '\n'
      printf '"}'
    } > "$body"
    rm -f "$enc"

    code=$(curl -sS --max-time 120 -o "$DIR/last-response.json" -w '%{http_code}' -X PUT \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      --data-binary @"$body" \
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
