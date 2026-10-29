#!/bin/bash
# Builds Mail Menu and runs it in demo mode: made-up accounts, mail and events from a fake Google server inside
# the app. Nothing goes over the network and your real accounts and Keychain aren't touched, so it's safe to
# use for development, screenshots and PRs. Demo data resets every time the app quits.
#
# Usage:
#   scripts/demo.sh           Open the panel with demo data. Quit from the panel's power button.
#   scripts/demo.sh --script  Walk through deleting, archiving, collapsing, switching filters, signing out and in,
#                             saving a snapshot of the panel after each step, then quit. Prints where the snapshots
#                             are, and whether the window ever failed to match its content's size.
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR="app/build-demo"
APP="${BUILD_DIR}/Build/Products/Debug/MailMenu.app"

# Built without the App Sandbox, so the snapshots land somewhere readable (sandboxed apps can't write outside
# their container). Demo mode makes no network requests either way. No Google client ID is needed.
xcodebuild -project app/MailMenu.xcodeproj -scheme MailMenu -configuration Debug -derivedDataPath "${BUILD_DIR}" \
  -destination "platform=macOS,arch=$(uname -m)" CODE_SIGN_ENTITLEMENTS= ENABLE_APP_SANDBOX=NO -quiet

# Quit a previous demo copy, but not the installed app.
pkill -f "${APP}/Contents/MacOS/MailMenu" || true

if [[ "${1:-}" == "--script" ]]; then
  "${APP}/Contents/MacOS/MailMenu" --demo --script 2>/dev/null
else
  "${APP}/Contents/MacOS/MailMenu" --demo --open >/dev/null 2>&1 &
  echo "Mail Menu is running in demo mode (look for a second envelope in the menu bar if the real app is running too)."
fi
