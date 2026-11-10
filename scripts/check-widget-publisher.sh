#!/bin/bash
set -euo pipefail

# Executes the production publisher's XCTest cases without launching/stopping PitPulse.
root="$(cd "$(dirname "$0")/.." && pwd)"
products="$HOME/Library/Caches/PitPulse/XcodeDevelopment/Build/Products/Debug"
if [[ ! -f "$products/PitPulseData.o" || ! -f "$products/PitPulseShared.o" ]]; then
    printf '%s\n' 'Run Taskdeck Build App Tests first to build the shared modules.' >&2
    exit 1
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/pitpulse-widget-tests.XXXXXX")"
bundle="$scratch/PitPulseWidgetTests.xctest"
mkdir -p "$bundle/Contents/MacOS"
/usr/bin/xcrun swiftc -emit-library -D WIDGET_STANDALONE \
    -module-name PitPulseWidgetTests \
    -target "$(uname -m)-apple-macosx26.0" \
    -I "$products" \
    -L "$(xcode-select -p)/Platforms/MacOSX.platform/Developer/usr/lib" \
    -Xlinker -rpath -Xlinker "$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks" \
    -F "$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks" \
    -framework XCTest \
    "$products/PitPulseShared.o" "$products/PitPulseData.o" \
    "$root/Shared/Widgets/WidgetSnapshotPublisher.swift" \
    "$root/Shared/Widgets/WidgetSnapshotPublisherTests.swift" \
    -o "$bundle/Contents/MacOS/PitPulseWidgetTests"
/usr/bin/xcrun xctest "$bundle"
# Leave the tiny result bundle in the OS temporary area; no computed-path deletion.
