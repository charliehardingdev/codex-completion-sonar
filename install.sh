#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="CompletionSonar"
APP_PATH="$HOME/Applications/${APP_NAME}.app"
LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/dev.codex.completion-sonar.plist"
LOG_DIR="$HOME/.codex/log"

mkdir -p "$LOG_DIR" "$HOME/Library/LaunchAgents" "$HOME/Applications"

"$SCRIPT_DIR/build.sh"

cat > "$LAUNCH_AGENT_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.codex.completion-sonar</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-gj</string>
        <string>$APP_PATH</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>$LOG_DIR/completion-sonar.out.log</string>

    <key>StandardErrorPath</key>
    <string>$LOG_DIR/completion-sonar.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PATH"
open -gj "$APP_PATH"

osascript <<APPLESCRIPT >/dev/null 2>&1 || true
tell application "System Events"
    if not (exists login item "CompletionSonar") then
        make login item at end with properties {path:"$APP_PATH", hidden:false}
    end if
end tell
APPLESCRIPT

echo "Installed Completion Sonar"
