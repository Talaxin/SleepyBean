#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/feather/app-repo.json"
IPA_PATH="$ROOT/BabySleepTracker/build/SleepyBean.ipa"
REPO="${GITHUB_REPOSITORY:-Talaxin/SleepyBean}"

if [[ ! -f "$IPA_PATH" ]]; then
  echo "ERROR: IPA not found at $IPA_PATH" >&2
  exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: Manifest not found at $MANIFEST" >&2
  exit 1
fi

VERSION="${APP_VERSION:-1.0.0}"
BUILD="${GITHUB_RUN_NUMBER:-0}"
FULL_VERSION="${VERSION}.${BUILD}"
TAG="v${FULL_VERSION}"
DATE="${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
SIZE="$(wc -c < "$IPA_PATH" | tr -d ' ')"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/SleepyBean.ipa"

echo "Updating Feather manifest:"
echo "  version: $FULL_VERSION"
echo "  size: $SIZE"
echo "  url: $DOWNLOAD_URL"

python3 - "$MANIFEST" "$FULL_VERSION" "$DATE" "$SIZE" "$DOWNLOAD_URL" <<'PY'
import json
import sys

path, version, date, size, url = sys.argv[1:6]
with open(path, encoding="utf-8") as f:
    data = json.load(f)

app = data["apps"][0]
app["version"] = version
app["versionDate"] = date
app["size"] = int(size)
app["downloadURL"] = url
app["versions"][0].update({
    "version": version,
    "date": date,
    "size": int(size),
    "downloadURL": url,
})

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

echo "==> feather/app-repo.json updated"
