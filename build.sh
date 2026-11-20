#!/bin/bash
set -eu
cd "$(dirname "$0")"
app="build/PhotoGather.app"
mkdir -p "$app/Contents/MacOS" build/module-cache
resources="$app/Contents/Resources"
mkdir -p "$resources"
cp Info.plist "$app/Contents/Info.plist"
cp Resources/PhotoGather.icns "$resources/"
# Icon Composer assets require Xcode 26 or later. CLT-only builds use the bundled ICNS.
if xcrun --find actool >/dev/null 2>&1 && [[ "$(xcodebuild -version | awk '/^Xcode / {print int($2)}')" -ge 26 ]]; then
    xcrun actool Resources/PhotoGather.icon --compile "$resources" --platform macosx \
        --target-device mac --minimum-deployment-target 13.0 --app-icon PhotoGather \
        --output-partial-info-plist build/icon-info.plist
    test -s "$resources/Assets.car"
    /usr/bin/plutil -insert CFBundleIconName -string PhotoGather "$app/Contents/Info.plist"
elif [[ -f "$resources/Assets.car" ]]; then
    rm "$resources/Assets.car"
fi
swiftc -O -swift-version 5 -module-cache-path build/module-cache -target "$(uname -m)-apple-macos13.0" Sources/*.swift Sources/{Domain,Application,Infrastructure,Presentation}/*.swift -o "$app/Contents/MacOS/PhotoGather"
codesign --force --sign - "$app"
