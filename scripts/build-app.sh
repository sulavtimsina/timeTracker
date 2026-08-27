#!/bin/bash
# Build TimeTracker.app from the Swift package.
#
#   scripts/build-app.sh            # builds dist/TimeTracker.app
#   scripts/build-app.sh --install  # also copies it to /Applications and launches it
#
# To regenerate the icon from source: swift packaging/makeicon.swift icon1024.png
# then rebuild packaging/AppIcon.icns with iconutil (see README).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=dist/TimeTracker.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TimeTracker "$APP/Contents/MacOS/TimeTracker"
cp packaging/Info.plist "$APP/Contents/Info.plist"
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    # Quit a running copy before replacing it.
    osascript -e 'tell application "TimeTracker" to quit' >/dev/null 2>&1 || true
    sleep 1
    rm -rf /Applications/TimeTracker.app
    cp -R "$APP" /Applications/TimeTracker.app
    open /Applications/TimeTracker.app
    echo "Installed and launched /Applications/TimeTracker.app"
fi
