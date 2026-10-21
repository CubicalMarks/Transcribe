#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep the chosen identity outside Git and never execute local configuration.
if [[ ${CODE_SIGN_IDENTITY+x} ]]; then
    signing_identity="$CODE_SIGN_IDENTITY"
elif [[ -f .signing-identity ]]; then
    IFS= read -r signing_identity < .signing-identity
else
    signing_identity="-"
fi
if [[ -z "$signing_identity" ]]; then
    printf 'Signing identity is empty. Set CODE_SIGN_IDENTITY or .signing-identity.\n' >&2
    exit 1
fi
if [[ "$signing_identity" == "-" ]]; then
    printf 'Warning: ad-hoc signing cannot preserve Keychain approval across builds. Configure a certificate for regular use.\n' >&2
fi

swift build -c release --arch arm64 --product Transcribe
bin_path=$(swift build -c release --arch arm64 --show-bin-path)
stage_path=$(mktemp -d "$PWD/.build/app-stage.XXXXXX")
app_path="$stage_path/Transcribe.app"
output_path="$PWD/dist/Transcribe.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/Transcribe" "$app_path/Contents/MacOS/Transcribe"
cp resources/Info.plist "$app_path/Contents/Info.plist"
cp resources/ThirdPartyNotices.md "$app_path/Contents/Resources/"
install -m 644 .build/checkouts/argmax-oss-swift/LICENSE "$app_path/Contents/Resources/Argmax-LICENSE.txt"
install -m 644 .build/checkouts/argmax-oss-swift/NOTICES "$app_path/Contents/Resources/Argmax-NOTICES.txt"
install -m 644 .build/checkouts/FluidAudio/LICENSE "$app_path/Contents/Resources/FluidAudio-LICENSE.txt"
install -m 644 .build/checkouts/FluidAudio/ThirdPartyLicenses/fastcluster-LICENSE.md "$app_path/Contents/Resources/FluidAudio-fastcluster-LICENSE.md"
for dependency in jwt-kit swift-crypto swift-certificates swift-asn1 swift-log; do
    for notice in LICENSE LICENSE.txt NOTICE.txt; do
        source_path=".build/checkouts/$dependency/$notice"
        if [[ -f "$source_path" ]]; then
            install -m 644 "$source_path" "$app_path/Contents/Resources/$dependency-$notice"
        fi
    done
done
mkdir -p .build/icon-cache
swift -module-cache-path .build/icon-cache scripts/AppIcon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns .build/AppIcon.iconset -o "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --sign "$signing_identity" --timestamp=none --options runtime --entitlements resources/entitlements.plist "$app_path"
codesign --verify --deep --strict "$app_path"
swift -module-cache-path .build/icon-cache scripts/InstallApp.swift "$app_path" "$output_path"
codesign --verify --deep --strict "$output_path"
printf 'Built: %s\n' "$output_path"
