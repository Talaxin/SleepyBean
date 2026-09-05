#!/usr/bin/env bash
set -euo pipefail

IPA_PATH="${1:-}"
if [[ -z "$IPA_PATH" || ! -f "$IPA_PATH" ]]; then
  echo "Usage: validate-ipa.sh <path-to.ipa>" >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

unzip -q "$IPA_PATH" -d "$WORKDIR"

APP_PATH="$(find "$WORKDIR/Payload" -name '*.app' -type d | head -n 1)"
if [[ -z "$APP_PATH" || ! -f "$APP_PATH/Info.plist" ]]; then
  echo "ERROR: Missing .app bundle in IPA Payload" >&2
  exit 1
fi

if [[ -d "$APP_PATH/PlugIns" ]]; then
  echo "ERROR: IPA contains PlugIns; sideload builds must not embed extensions" >&2
  find "$APP_PATH/PlugIns" -maxdepth 2 -type f | sed 's/^/  /'
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"
DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP_PATH/Info.plist" 2>/dev/null || true)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Info.plist")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$APP_PATH/Info.plist" 2>/dev/null || echo "unknown")"

if [[ "$BUNDLE_ID" != "com.sleepybean.tracker" ]]; then
  echo "ERROR: Unexpected bundle id: $BUNDLE_ID" >&2
  exit 1
fi

if [[ -z "$DISPLAY_NAME" ]]; then
  echo "ERROR: CFBundleDisplayName is missing" >&2
  exit 1
fi

if [[ ! -f "$APP_PATH/AppIcon60x60@2x.png" && ! -f "$APP_PATH/Assets.car" ]]; then
  echo "ERROR: App icon assets missing from IPA" >&2
  exit 1
fi

echo "IPA validation passed"
echo "  bundle_id=$BUNDLE_ID"
echo "  display_name=$DISPLAY_NAME"
echo "  version=$VERSION"
echo "  build=$BUILD"
echo "  min_os=$MIN_OS"
echo "  size=$(wc -c < "$IPA_PATH" | tr -d ' ')"
