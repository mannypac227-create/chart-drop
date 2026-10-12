#!/bin/bash
# Unscramble the trader's own chart screenshots (scrambled by his Mac uploader)
# so the hourly brief can look at them.
# Usage: bash tools/unscramble.sh [minutes]   (default 75)
# Reads the key from $HOME/.chart-drop-key (one line). Writes images to $HOME/charts-plain
# and prints one line per image: <New York time>  <path>
set -u
MIN="${1:-75}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYFILE="$HOME/.chart-drop-key"
OUT="$HOME/charts-plain"
[ -s "$KEYFILE" ] || { echo "ERROR: key file $KEYFILE missing"; exit 1; }
mkdir -p "$OUT"
cutoff=$(TZ=America/New_York date -d "-$MIN minutes" +%Y-%m-%d_%H-%M-%S)
found=0; ok=0
for f in $(ls "$ROOT"/shots/*/*.enc 2>/dev/null | sort -r); do
  name=$(basename "$f" .enc)
  stamp=$(echo "$name" | cut -d_ -f1-2)        # YYYY-MM-DD_HH-MM-SS (New York time)
  [[ "$stamp" < "$cutoff" ]] && continue
  found=$((found+1))
  [ "$ok" -ge 8 ] && continue                   # keep the 8 newest
  if openssl enc -d -aes-256-cbc -md sha256 -in "$f" -out "$OUT/$name" -pass "file:$KEYFILE" 2>/dev/null; then
    ok=$((ok+1)); echo "${stamp/_/ } ET  $OUT/$name"
  else
    echo "FAILED: $name"
  fi
done
echo "Found $found screenshot(s) from the last $MIN minutes; unscrambled $ok."
