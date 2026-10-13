# chart-drop

Screenshots for two scheduled agents, in separate lanes:

- `shots/` ← `~/Dropbox/Charts`: trading charts for the Hourly Forex & Gold Brief. Days older than yesterday are deleted automatically.
- `wholesale/` ← `~/Dropbox/Wholesale`: property listing screenshots for the Wholesale Property Reader. Days older than 7 days are deleted automatically.

- `mac/install-template.sh` + `mac/upload.sh`: the Mac helper. Each new chart saved in `~/Dropbox/Charts` is uploaded here. Other screenshots are never uploaded.
- `shots/YYYY-MM-DD/`: the uploaded charts, named `YYYY-MM-DD_HH-MM-SS_charts_<id>.png` in New York time. Days older than yesterday are deleted automatically.
- The cloud hourly brief reads the newest charts each hour, so it works even when the Mac is closed.

Remove from the Mac: `bash install-chart-drop.sh --uninstall`. Upload log on the Mac: `~/.chart-drop/upload.log`.
