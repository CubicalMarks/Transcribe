#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --product Transcribe
bin_path=$(swift build -c release --arch arm64 --show-bin-path)
app_path="$PWD/dist/Transcribe.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/Transcribe" "$app_path/Contents/MacOS/Transcribe"
cp resources/Info.plist "$app_path/Contents/Info.plist"
cp resources/ThirdPartyNotices.md "$app_path/Contents/Resources/"
install -m 644 .build/checkouts/argmax-oss-swift/LICENSE "$app_path/Contents/Resources/Argmax-LICENSE.txt"
install -m 644 .build/checkouts/argmax-oss-swift/NOTICES "$app_path/Contents/Resources/Argmax-NOTICES.txt"
mkdir -p .build/icon-cache
swift -module-cache-path .build/icon-cache scripts/AppIcon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns .build/AppIcon.iconset -o "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --sign - --options runtime --entitlements resources/entitlements.plist "$app_path"
codesign --verify --deep --strict "$app_path"
printf 'Built: %s\n' "$app_path"
