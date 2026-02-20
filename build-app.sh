#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="OpenClaw Vox"
BUNDLE_NAME="${APP_NAME}.app"
BUILD_DIR="${SCRIPT_DIR}/dist"
BUNDLE_DIR="${BUILD_DIR}/${BUNDLE_NAME}"

echo "Building OpenClaw Vox release binary..."
cd "$SCRIPT_DIR"
swift build -c release

# Resolve binary path (arm64 or x86_64)
BIN=$(swift build -c release --show-bin-path)/OpenClawVox

if [ ! -f "$BIN" ]; then
    echo "Error: binary not found at $BIN"
    exit 1
fi

echo "Creating app bundle..."
rm -rf "$BUNDLE_DIR"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"

cp "$BIN" "${BUNDLE_DIR}/Contents/MacOS/OpenClawVox"
cp "${SCRIPT_DIR}/Info.plist" "${BUNDLE_DIR}/Contents/"

echo "Code signing..."
codesign --force --sign - \
    --entitlements "${SCRIPT_DIR}/entitlements.plist" \
    --deep \
    "$BUNDLE_DIR"

echo ""
echo "Done! App bundle created at:"
echo "  ${BUNDLE_DIR}"
echo ""
echo "To install:"
echo "  cp -R \"${BUNDLE_DIR}\" /Applications/"
echo ""
echo "Then open it from /Applications or Spotlight."
echo "Use the 'Start at Login' toggle in the menu bar dropdown to launch on login."
