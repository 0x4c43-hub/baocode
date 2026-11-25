#!/usr/bin/env bash
#
# Installs (or removes) the LaunchAgent that runs tool/autoupdate_custom.sh:
# at login, and every day at 12:30. It checks the upstream for new commits,
# and when there are some, merges, tests, builds, and installs BaoCode 2
# (while it is not running).
#
#   tool/install_autoupdate.sh              install, and run a check now
#   tool/install_autoupdate.sh --uninstall  remove it
#   tool/install_autoupdate.sh --check      only check the upstream now
#
# Logs: ~/Library/Logs/BaoCode2-autoupdate.log

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="dev.baocode.baocode2.autoupdate"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/BaoCode2-autoupdate.log"
LAUNCH_LOG="$HOME/Library/Logs/BaoCode2-autoupdate.launchd.log"
LAUNCHER="$HOME/Library/Application Support/BaoCode2/autoupdate-launch.sh"

uninstall() {
  launchctl bootout "gui/$UID" "$PLIST" >/dev/null 2>&1 || true
  rm -f "$PLIST"
  echo "Removed $LABEL."
}

case "${1:-}" in
  --uninstall) uninstall; exit 0 ;;
  --check) exec "$ROOT/tool/autoupdate_custom.sh" --check ;;
  "") ;;
  *) echo "Unknown option: $1" >&2; exit 1 ;;
esac

mkdir -p "$HOME/Library/LaunchAgents" "$(dirname "$LOG")"
mkdir -p "$(dirname "$LAUNCHER")"

# launchd's job must be able to start: this folder is not on the checkout's
# volume, which macOS may keep background jobs out of (an external disk sees
# "Operation not permitted"). The launcher says so, once a day, when the
# checkout cannot be read, instead of the job failing without a word.
cat >"$LAUNCHER" <<LAUNCHER_END
#!/bin/bash
ROOT="$ROOT"
LOG="$LOG"
STAMP="\$HOME/Library/Application Support/BaoCode2/unreadable-notified"
if ! /bin/ls "\$ROOT" >/dev/null 2>&1; then
  echo "\$(date '+%Y-%m-%d %H:%M:%S') cannot read \$ROOT: macOS keeps this background job from the volume it is on" >>"\$LOG"
  today="\$(date '+%Y-%m-%d')"
  if [ "\$(cat "\$STAMP" 2>/dev/null)" != "\$today" ]; then
    echo "\$today" >"\$STAMP"
    /usr/bin/osascript -e 'display notification "后台任务读不到代码目录（外置磁盘受隐私保护）。在 系统设置 → 隐私与安全性 → 完全磁盘访问权限 里授权 /bin/bash，或手动运行 tool/autoupdate_custom.sh" with title "BaoCode 2 自动更新"' >/dev/null 2>&1 || true
  fi
  exit 0
fi
exec /bin/bash "\$ROOT/tool/autoupdate_custom.sh" --quiet
LAUNCHER_END
chmod +x "$LAUNCHER"

cat >"$PLIST" <<PLIST_END
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$LAUNCHER</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>12</integer>
    <key>Minute</key>
    <integer>30</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>$LAUNCH_LOG</string>
  <key>StandardErrorPath</key>
  <string>$LAUNCH_LOG</string>
</dict>
</plist>
PLIST_END

launchctl bootout "gui/$UID" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$PLIST"

echo "Installed $LABEL: at login, and every day at 12:30."
echo "Checks now:"
"$ROOT/tool/autoupdate_custom.sh" --check
echo
echo "Logs: $LOG"
echo "Remove it with: tool/install_autoupdate.sh --uninstall"
