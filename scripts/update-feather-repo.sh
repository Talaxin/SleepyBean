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

chmod +x "$ROOT/scripts/read-ipa-metadata.sh"
eval "$("$ROOT/scripts/read-ipa-metadata.sh" "$IPA_PATH")"

TAG="v${full_version}"
DATE="${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/SleepyBean.ipa"
ICON_URL="https://raw.githubusercontent.com/${REPO}/main/feather/icon.png"

echo "Updating Feather manifest from IPA metadata:"
echo "  version: $full_version"
echo "  bundle: $bundle_id"
echo "  size: $size"
echo "  url: $DOWNLOAD_URL"

python3 - "$MANIFEST" "$full_version" "$DATE" "$size" "$DOWNLOAD_URL" "$ICON_URL" "$bundle_id" <<'PY'
import json
import sys

path, version, date, size, url, icon_url, bundle_id = sys.argv[1:8]
with open(path, encoding="utf-8") as f:
    data = json.load(f)

app = data["apps"][0]
app["bundleIdentifier"] = bundle_id
app["version"] = version
app["versionDate"] = date
app["size"] = int(size)
app["downloadURL"] = url
app["iconURL"] = icon_url
app["versions"][0].update({
    "version": version,
    "date": date,
    "size": int(size),
    "downloadURL": url,
})
data["iconURL"] = icon_url

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

echo "==> feather/app-repo.json updated from IPA"
