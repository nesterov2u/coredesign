#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
source scripts/sparkle.sh

app="${1:-CoreDesign.app}"
version="${COREDESIGN_VERSION:-0.2.0}"
build="${COREDESIGN_BUILD_NUMBER:-2}"
signing_identity="${COREDESIGN_CODESIGN_IDENTITY:--}"
default_feed="https://github.com/nesterov2u/coredesign/releases/latest/download/appcast.xml"
feed="${COREDESIGN_FEED_URL:-$default_feed}"
module_cache="${COREDESIGN_BUILD_CACHE:-.build}/modules"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[1-9][0-9]*$ ]] || {
    echo "Expected a numeric version (x.y.z) and a positive build number." >&2
    exit 1
}
prepare_sparkle
mkdir -p "$module_cache" "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"

xcrun swiftc -O -parse-as-library \
    -target "$(uname -m)-apple-macosx14.0" \
    -module-cache-path "$module_cache" \
    -F "$sparkle_cache" -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    Sources/CoreDesign/*.swift -o "$app/Contents/MacOS/CoreDesign"

ditto Sources/CoreDesign/Fonts "$app/Contents/Resources/Fonts"
ditto "$sparkle_cache/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp "$sparkle_cache/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE.txt"

info="$app/Contents/Info.plist"
cat > "$info" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>ru</string>
    <key>CFBundleDisplayName</key><string>CoreDesign</string>
    <key>CFBundleExecutable</key><string>CoreDesign</string>
    <key>CFBundleIdentifier</key><string>local.coredesign.prototype</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>CoreDesign</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>SUVerifyUpdateBeforeExtraction</key><true/>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUAllowsAutomaticUpdates</key><false/>
</dict>
</plist>
PLIST

plutil -insert CFBundleShortVersionString -string "$version" "$info"
plutil -insert CFBundleVersion -string "$build" "$info"
plutil -insert SUFeedURL -string "$feed" "$info"
plutil -insert SUPublicEDKey -string "$(cat scripts/update-public-key.txt)" "$info"

framework="$app/Contents/Frameworks/Sparkle.framework"
sign_options=(--force --sign "$signing_identity")
if [[ "$signing_identity" != "-" ]]; then
    sign_options+=(--timestamp --options runtime)
fi
for component in "$framework"/Versions/B/XPCServices/*.xpc \
                 "$framework/Versions/B/Autoupdate" "$framework/Versions/B/Updater.app" \
                 "$framework/Versions/B"; do
    codesign "${sign_options[@]}" "$component"
done
codesign "${sign_options[@]}" "$app"
codesign --verify --deep --strict "$app"
