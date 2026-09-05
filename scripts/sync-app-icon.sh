#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON_SRC="$ROOT/feather/icon.png"
ICON_DEST="$ROOT/BabySleepTracker/BabySleepTracker/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

if [[ ! -f "$ICON_SRC" ]]; then
  echo "ERROR: Source icon not found at $ICON_SRC" >&2
  exit 1
fi

mkdir -p "$(dirname "$ICON_DEST")"
cp "$ICON_SRC" "$ICON_DEST"
echo "==> Synced app icon to asset catalog"
