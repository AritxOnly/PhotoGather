#!/bin/bash
set -eu
cd "$(dirname "$0")"
mkdir -p build/module-cache
swiftc -module-cache-path build/module-cache Sources/Domain/*.swift Sources/Application/*.swift Sources/Infrastructure/LocalMedia.swift Tests/main.swift -o build/core-tests
build/core-tests
