#!/bin/bash
# Chart Drop installer. Run once on the Mac:  bash ~/Downloads/install-chart-drop.sh
# It saves your GitHub key in the Mac Keychain and installs a small background
# helper that scrambles each new chart screenshot and uploads it to github.com/mannypac227-create/chart-drop.
# To remove it later:  bash ~/Downloads/install-chart-drop.sh --uninstall
set -e

REPO="mannypac227-create/chart-drop"
DIR="$HOME/.chart-drop"
LABEL="com.chartdrop.uploader"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM=$(id -u)

if [ "${1:-}" = "--uninstall" ]; then
  launchctl bootout "gui/$UID_NUM" "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  security delete-generic-password -s chart-drop -a github >/dev/null 2>&1 || true
  security delete-generic-password -s chart-drop -a scramble >/dev/null 2>&1 || true
  rm -rf "$DIR"
  echo "Chart Drop removed from this Mac."
  exit 0
fi

echo ""
echo "== Chart Drop setup =="
mkdir -p "$DIR" "$HOME/Library/LaunchAgents"

# 1. GitHub key, kept in the Mac Keychain.
if security find-generic-password -s chart-drop -a github >/dev/null 2>&1; then
  echo "A GitHub key is already saved. Press Return to keep it, or type new and press Return to replace it."
  read -r ans
  if [ "$ans" = "new" ]; then
    security delete-generic-password -s chart-drop -a github >/dev/null 2>&1 || true
  fi
fi
if ! security find-generic-password -s chart-drop -a github >/dev/null 2>&1; then
  echo "Paste your GitHub key and press Return (nothing shows while you paste, that's normal):"
  read -rs TOKEN
  echo ""
  if [ -z "$TOKEN" ]; then echo "No key entered. Run this again."; exit 1; fi
  code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" "https://api.github.com/repos/$REPO")
  if [ "$code" != "200" ]; then
    echo "That key can't open chart-drop (GitHub said $code)."
    echo "Make sure it has access to the chart-drop repository with Contents set to Read and write."
    exit 1
  fi
  security add-generic-password -U -s chart-drop -a github -w "$TOKEN"
  unset TOKEN
  echo "GitHub key saved in your Keychain."
fi

# 2. The scramble key (the hourly brief has the same key, so only it can read the uploads).
security add-generic-password -U -s chart-drop -a scramble -w "__SCRAMBLE_KEY__"

# 3. The uploader script.
cat > "$DIR/upload.sh" <<'CHARTDROP_EOF'
__UPLOADER__
CHARTDROP_EOF
chmod +x "$DIR/upload.sh"

# 4. Run it in the background whenever a screenshot lands, and every 5 minutes.
SHOTS=$(cd "$HOME/Dropbox/Screenshots" 2>/dev/null && pwd -P || echo "$HOME/Dropbox/Screenshots")
CHARTS=$(cd "$HOME/Dropbox/Charts" 2>/dev/null && pwd -P || echo "$HOME/Dropbox/Charts")
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$DIR/upload.sh</string></array>
  <key>WatchPaths</key>
  <array><string>$SHOTS</string><string>$CHARTS</string></array>
  <key>StartInterval</key><integer>300</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$DIR/launchd.log</string>
  <key>StandardErrorPath</key><string>$DIR/launchd.log</string>
</dict>
</plist>
PLIST_EOF

launchctl bootout "gui/$UID_NUM" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST"

# 5. Upload anything from the last 24 hours right now, so you can see it work.
echo "Uploading your recent screenshots now..."
/bin/bash "$DIR/upload.sh" || true
echo ""
if [ -s "$DIR/upload.log" ]; then
  tail -n 5 "$DIR/upload.log"
else
  echo "No screenshots from the last 24 hours to upload yet."
fi
echo ""
echo "Done. New screenshots will now upload to GitHub by themselves."
echo "If macOS asks whether bash may access files in Dropbox, click Allow."
