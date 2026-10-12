# chart-drop

Scrambled chart screenshots for the Hourly Forex & Gold Brief.

- `mac/install-template.sh` + `mac/upload.sh` — the Mac helper. Each new screenshot from `~/Dropbox/Screenshots` and `~/Dropbox/Charts` is scrambled (AES-256) on the Mac, then uploaded here.
- `shots/YYYY-MM-DD/*.enc` — the scrambled screenshots. They can't be viewed without the key, which is only on the Mac (Keychain) and in the hourly brief.
- The cloud hourly brief downloads the newest files each hour and unscrambles them, so it works even when the Mac is closed.

Remove from the Mac: `bash install-chart-drop.sh --uninstall`. Upload log on the Mac: `~/.chart-drop/upload.log`.
