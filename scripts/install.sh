#!/bin/bash
# Builds Mail Menu in Release mode, installs it to /Applications and launches it.
# Run it again to update after pulling new changes. Usage: scripts/install.sh
#
# Set INSTALL_DIR to install somewhere else, e.g. INSTALL_DIR=~/Applications scripts/install.sh
set -euo pipefail

cd "$(dirname "$0")/.."

INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP_NAME="MailMenu.app"
BUILD_DIR="app/build"
LOCAL_CONFIG="app/Config/Local.xcconfig"

if ! grep -Eq '^GOOGLE_CLIENT_ID *= *[^ ]+' "${LOCAL_CONFIG}" 2>/dev/null; then
  echo "error: set GOOGLE_CLIENT_ID in ${LOCAL_CONFIG} first (see the README's setup steps)." >&2
  exit 1
fi

echo "Building Mail Menu..."
xcodebuild -project app/MailMenu.xcodeproj -scheme MailMenu -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "${BUILD_DIR}" -allowProvisioningUpdates -quiet

# Quit the running copy (if any) so it can be replaced.
if pgrep -x MailMenu >/dev/null; then
  echo "Quitting the running copy..."
  pkill -x MailMenu || true
  while pgrep -x MailMenu >/dev/null; do sleep 0.2; done
fi

echo "Installing to ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}"
rm -rf "${INSTALL_DIR:?}/${APP_NAME}"
ditto "${BUILD_DIR}/Build/Products/Release/${APP_NAME}" "${INSTALL_DIR}/${APP_NAME}"

open "${INSTALL_DIR}/${APP_NAME}"
echo "Done. Mail Menu is running from ${INSTALL_DIR}/${APP_NAME}."
