#!/usr/bin/env bash
set -euo pipefail

IPA_PATH="${1:-}"
if [[ -z "$IPA_PATH" || ! -f "$IPA_PATH" ]]; then
  echo "Usage: read-ipa-metadata.sh <path-to.ipa>" >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

unzip -q "$IPA_PATH" -d "$WORKDIR"
APP_PATH="$(find "$WORKDIR/Payload" -name '*.app' -type d | head -n 1)"

if [[ -z "$APP_PATH" || ! -f "$APP_PATH/Info.plist" ]]; then
  echo "ERROR: Could not find Info.plist inside IPA" >&2
  exit 1
fi

MARKETING_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Info.plist")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"
DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP_PATH/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$APP_PATH/Info.plist")"
FULL_VERSION="${MARKETING_VERSION}.${BUILD_NUMBER}"
SIZE="$(wc -c < "$IPA_PATH" | tr -d ' ')"

HAS_ICON="no"
if [[ -f "$APP_PATH/AppIcon60x60@2x.png" || -f "$APP_PATH/AppIcon76x76@2x~ipad.png" ]]; then
  HAS_ICON="yes"
fi
if compgen -G "$APP_PATH/AppIcon*.png" > /dev/null || compgen -G "$APP_PATH/*.car" > /dev/null; then
  HAS_ICON="yes"
fi

echo "marketing_version=$MARKETING_VERSION"
echo "build_number=$BUILD_NUMBER"
echo "full_version=$FULL_VERSION"
echo "bundle_id=$BUNDLE_ID"
echo "display_name=$DISPLAY_NAME"
echo "size=$SIZE"
echo "has_icon=$HAS_ICON"
