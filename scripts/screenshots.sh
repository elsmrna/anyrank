#!/usr/bin/env bash
# Regenerates the README screenshots in docs/screenshots/.
#
# Builds a Debug build for a dedicated "AnyRank Screenshots" Simulator (created
# on first run, so your everyday Simulator's data is never touched), installs
# it fresh with the demo data, opens each screen listed in ROUTES (via the Debug-only
# `-screenshotRoute` launch argument, see AnyRank/Preview/ScreenshotRoute.swift),
# and captures it in light and dark mode with a clean status bar.
#
# Usage: scripts/screenshots.sh [route ...]
#   No arguments captures every route. Environment overrides:
#     DEVICE   Device type for the screenshot Simulator (default: iPhone 17 Pro)
#     WIDTH    Output width in pixels (default: 600)
#     SETTLE   Seconds to wait for a screen and its artwork (default: 4)
set -euo pipefail

cd "$(dirname "$0")/.."

ROUTES=(home list bucketPick compare importSources)
[[ $# -gt 0 ]] && ROUTES=("$@")

DEVICE="${DEVICE:-iPhone 17 Pro}"
SIM_NAME="AnyRank Screenshots ($DEVICE)"
WIDTH="${WIDTH:-600}"
SETTLE="${SETTLE:-4}"
BUNDLE_ID="com.ellismiranda.anyrank.AnyRank"
OUT_DIR="docs/screenshots"
DERIVED_DATA=".build/screenshots"
mkdir -p .build

# xcode-select may point at the Command Line Tools; use the full Xcode.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

[[ -f Secrets.xcconfig ]] || cp Secrets.xcconfig.example Secrets.xcconfig
command -v xcodegen >/dev/null || { echo "Install xcodegen: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet

UDID=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
for devices in json.load(sys.stdin)['devices'].values():
    for d in devices:
        if d['name'] == sys.argv[1]:
            print(d['udid']); sys.exit()
" "$SIM_NAME")
if [[ -z "$UDID" ]]; then
  echo "Creating the $SIM_NAME Simulator…"
  UDID=$(xcrun simctl create "$SIM_NAME" "$DEVICE")
fi

echo "Building for $SIM_NAME…"
xcodebuild build \
  -project AnyRank.xcodeproj -scheme AnyRank -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" -quiet > "$DERIVED_DATA.log" 2>&1 \
  || { grep -E 'error:' "$DERIVED_DATA.log" >&2; echo "Build failed; full log: $DERIVED_DATA.log" >&2; exit 1; }
APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/AnyRank.app"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl status_bar "$UDID" override \
  --time 9:41 --dataNetwork wifi --wifiBars 3 --cellularBars 4 \
  --batteryState discharging --batteryLevel 100

# Start from an empty container so the demo seed always runs.
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

mkdir -p "$OUT_DIR"
ORIGINAL_APPEARANCE=$(xcrun simctl ui "$UDID" appearance)
trap 'xcrun simctl ui "$UDID" appearance "$ORIGINAL_APPEARANCE"; xcrun simctl status_bar "$UDID" clear; xcrun simctl shutdown "$UDID" 2>/dev/null || true' EXIT

for appearance in light dark; do
  xcrun simctl ui "$UDID" appearance "$appearance"
  for route in "${ROUTES[@]}"; do
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE_ID" \
      -seedDemoData -hasCompletedOnboarding YES -screenshotRoute "$route" >/dev/null
    sleep "$SETTLE"
    file="$OUT_DIR/$route-$appearance.png"
    xcrun simctl io "$UDID" screenshot --type=png "$file" >/dev/null 2>&1
    sips --resampleWidth "$WIDTH" "$file" >/dev/null
    echo "  $file"
  done
done
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
