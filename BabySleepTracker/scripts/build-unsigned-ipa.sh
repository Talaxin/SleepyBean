#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SCHEME="BabySleepTracker"
PROJECT="BabySleepTracker.xcodeproj"
DERIVED_DATA="$ROOT/build/DerivedData"
OUTPUT_DIR="$ROOT/build"
IPA_PATH="$OUTPUT_DIR/SleepyBean.ipa"

MARKETING_VERSION="${MARKETING_VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

echo "==> Building SleepyBean ${MARKETING_VERSION} (${BUILD_NUMBER})..."

if [[ -f "$REPO_ROOT/scripts/sync-app-icon.sh" ]]; then
  bash "$REPO_ROOT/scripts/sync-app-icon.sh"
fi

rm -rf "$OUTPUT_DIR/Payload" "$IPA_PATH"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=NO

APP_PATH="$(find "$DERIVED_DATA" -path "*/Build/Products/Release-iphoneos/BabySleepTracker.app" -type d | head -n 1)"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "ERROR: Could not find built .app bundle" >&2
  find "$DERIVED_DATA" -name "*.app" -type d || true
  exit 1
fi

echo "==> Built app metadata:"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Info.plist" | xargs -I{} echo "  CFBundleShortVersionString: {}"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Info.plist" | xargs -I{} echo "  CFBundleVersion: {}"
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP_PATH/Info.plist" 2>/dev/null | xargs -I{} echo "  CFBundleDisplayName: {}" || true

echo "==> Packaging IPA from: $APP_PATH"
mkdir -p "$OUTPUT_DIR/Payload"
ditto "$APP_PATH" "$OUTPUT_DIR/Payload/BabySleepTracker.app"

# Sideload builds ship without extensions for reliable Feather installs.
if [[ -d "$OUTPUT_DIR/Payload/BabySleepTracker.app/PlugIns" ]]; then
  echo "==> Removing embedded extensions for sideload distribution"
  rm -rf "$OUTPUT_DIR/Payload/BabySleepTracker.app/PlugIns"
fi
(
  cd "$OUTPUT_DIR"
  rm -f "$IPA_PATH"
  zip -qr "$IPA_PATH" Payload
  rm -rf Payload
)

echo "==> Done: $IPA_PATH"
ls -lh "$IPA_PATH"
