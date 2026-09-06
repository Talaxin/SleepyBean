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
SOURCE_URL="https://raw.githubusercontent.com/${REPO}/main/feather/app-repo.json"

echo "Updating Feather manifest from IPA metadata:"
echo "  version: $full_version"
echo "  build: $build_number"
echo "  bundle: $bundle_id"
echo "  size: $size"
echo "  url: $DOWNLOAD_URL"

python3 - "$MANIFEST" "$full_version" "$build_number" "$DATE" "$size" "$DOWNLOAD_URL" "$ICON_URL" "$bundle_id" "$SOURCE_URL" <<'PY'
import json
import sys

path, version, build, date, size, url, icon_url, bundle_id, source_url = sys.argv[1:10]
with open(path, encoding="utf-8") as f:
    data = json.load(f)

data["sourceURL"] = source_url
data["iconURL"] = icon_url

app = data["apps"][0]
app["bundleIdentifier"] = bundle_id
app["iconURL"] = icon_url
app["version"] = version
app["versionDate"] = date
app["size"] = int(size)
app["downloadURL"] = url
app["appPermissions"] = {
    "entitlements": [
        "com.apple.developer.icloud-container-identifiers",
        "com.apple.developer.icloud-services",
        "com.apple.developer.ubiquity-container-identifiers"
    ],
    "privacy": {}
}

new_entry = {
    "version": version,
    "buildVersion": build,
    "date": date,
    "localizedDescription": f"SleepyBean {version} — feeding, day/night modes, wake windows.",
    "downloadURL": url,
    "size": int(size),
    "minOSVersion": "17.0",
}

versions = app.get("versions", [])
versions = [entry for entry in versions if entry.get("version") != version]
versions.insert(0, new_entry)
app["versions"] = versions[:5]

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

echo "==> feather/app-repo.json updated from IPA"
