#!/bin/bash
set -eu
cd "$(dirname "$0")"
app="build/PhotoGather.app"
mkdir -p "$app/Contents/MacOS" build/module-cache
cp Info.plist "$app/Contents/Info.plist"
swiftc -O -swift-version 5 -module-cache-path build/module-cache -target "$(uname -m)-apple-macos13.0" Sources/*.swift -o "$app/Contents/MacOS/PhotoGather"
codesign --force --sign - "$app"
