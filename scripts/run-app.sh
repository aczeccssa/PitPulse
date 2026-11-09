#!/bin/bash
set -euo pipefail

project="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="$HOME/Library/Caches/PitPulse/Xcode"
cd "$project"

printf '%s\n' 'Building PitPulse Desktop (Release)…'
/usr/bin/xcodebuild -quiet \
    -project PitPulse.xcodeproj \
    -scheme PitPulseDesktop \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" build

printf '%s\n' 'Starting the Release app connected to the real local server on port 38701.'
exec "$derived_data/Build/Products/Release/PitPulse.app/Contents/MacOS/PitPulse" \
    -serverAddress http://127.0.0.1:38701
