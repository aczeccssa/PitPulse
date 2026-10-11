#!/bin/bash
set -euo pipefail

project="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="$HOME/Library/Caches/PitPulse/Xcode"
cd "$project"

printf '%s\n' 'Building F1 Companion Release…'
/usr/bin/xcodebuild -quiet \
    -project macos/F1Companion.xcodeproj \
    -scheme F1Companion \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" build

printf '%s\n' 'Starting the Release app connected to the real local server on port 38701.'
exec "$derived_data/Build/Products/Release/F1Companion.app/Contents/MacOS/F1Companion" \
    -serverAddress http://127.0.0.1:38701
