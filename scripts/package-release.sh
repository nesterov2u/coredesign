#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
app="${1:?Usage: scripts/package-release.sh APP OUTPUT_DIR [DOWNLOAD_ROOT]}"
output="${2:?Usage: scripts/package-release.sh APP OUTPUT_DIR [DOWNLOAD_ROOT]}"
private_key="${COREDESIGN_SIGNING_KEY:-.release-signing/update.key}"
build_cache="${COREDESIGN_BUILD_CACHE:-.build}"
module_cache="$build_cache/modules"
info="$app/Contents/Info.plist"
version="$(plutil -extract CFBundleShortVersionString raw "$info")"
build="$(plutil -extract CFBundleVersion raw "$info")"
minimum_os="$(plutil -extract LSMinimumSystemVersion raw "$info")"
download_root="${3:-https://github.com/nesterov2u/coredesign/releases/download/v$version}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[1-9][0-9]*$ && "$minimum_os" =~ ^[0-9]+(\.[0-9]+)*$ && "$download_root" =~ ^https?://[a-zA-Z0-9./:_-]+$ ]]
[[ "$(plutil -extract SUPublicEDKey raw "$info")" == "$(cat scripts/update-public-key.txt)" ]]
[[ "$(basename "$app")" == "CoreDesign.app" ]]
codesign --verify --deep --strict "$app"

mkdir -p "$output" "$module_cache"
archive_name="CoreDesign-$version.zip"
archive="$output/$archive_name"
scratch="$(mktemp -d "$build_cache/coredesign-release.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$app" "$scratch/$archive_name"
signature="$(xcrun swift -module-cache-path "$module_cache" scripts/update-signing.swift sign "$private_key" scripts/update-public-key.txt "$scratch/$archive_name")"
size="$(stat -f %z "$scratch/$archive_name")"
cat > "$scratch/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>CoreDesign</title>
    <item>
      <title>CoreDesign $version</title>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum_os</sparkle:minimumSystemVersion>
      <enclosure url="$download_root/$archive_name"
                 length="$size" type="application/octet-stream"
                 sparkle:edSignature="$signature" />
    </item>
  </channel>
</rss>
XML
mv "$scratch/$archive_name" "$archive"
mv "$scratch/appcast.xml" "$output/appcast.xml"
printf '%s\n' "$archive" "$output/appcast.xml"
