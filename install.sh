#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="CodexCompletionSonar"
APP_BUNDLE_NAME="Codex Completion Sonar"
APP_PATH="$HOME/Applications/${APP_BUNDLE_NAME}.app"
LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/dev.codex.codex-completion-sonar.plist"
LEGACY_APP_PATH="$HOME/Applications/CompletionSonar.app"
LEGACY_COMPACT_APP_PATH="$HOME/Applications/CodexCompletionSonar.app"
LEGACY_LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/dev.codex.completion-sonar.plist"
LOG_DIR="$HOME/.codex/log"

mkdir -p "$LOG_DIR" "$HOME/Library/LaunchAgents" "$HOME/Applications"

"$SCRIPT_DIR/build.sh"

pkill -f '/Users/charlie/Applications/CompletionSonar.app/Contents/MacOS/CodexCompletionSonar' >/dev/null 2>&1 || true
pkill -f '/Users/charlie/Applications/CodexCompletionSonar.app/Contents/MacOS/CodexCompletionSonar' >/dev/null 2>&1 || true
pkill -f '/Users/charlie/Applications/Codex Completion Sonar.app/Contents/MacOS/CodexCompletionSonar' >/dev/null 2>&1 || true

launchctl bootout "gui/$(id -u)" "$LEGACY_LAUNCH_AGENT_PATH" >/dev/null 2>&1 || true
rm -f "$LEGACY_LAUNCH_AGENT_PATH"
rm -rf "$LEGACY_APP_PATH"
rm -rf "$LEGACY_COMPACT_APP_PATH"

cat > "$LAUNCH_AGENT_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.codex.codex-completion-sonar</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-gj</string>
        <string>$APP_PATH</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>$LOG_DIR/codex-completion-sonar.out.log</string>

    <key>StandardErrorPath</key>
    <string>$LOG_DIR/codex-completion-sonar.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PATH"
open -gj "$APP_PATH"

osascript <<APPLESCRIPT >/dev/null 2>&1 || true
tell application "System Events"
    if (exists login item "CompletionSonar") then
        delete login item "CompletionSonar"
    end if
    if (exists login item "CodexCompletionSonar") then
        delete login item "CodexCompletionSonar"
    end if
    if not (exists login item "Codex Completion Sonar") then
        make login item at end with properties {path:"$APP_PATH", hidden:false}
    end if
end tell
APPLESCRIPT

echo "Installed Codex Completion Sonar"
