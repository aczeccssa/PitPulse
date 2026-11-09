#!/bin/bash
set -euo pipefail

project="$(cd "$(dirname "$0")/.." && pwd)"
action="${1:-build}"
configuration="${2:-Debug}"
case "$action" in
    build|build-for-testing|test) ;;
    *) printf '%s\n' 'Expected build, build-for-testing, or test.' >&2; exit 2 ;;
esac
case "$configuration" in
    Debug|Release) ;;
    *) printf '%s\n' 'Expected Debug or Release configuration.' >&2; exit 2 ;;
esac
if [[ "$action" == test ]] && (/usr/bin/pgrep -x PitPulse >/dev/null || /usr/bin/pgrep -x F1Companion >/dev/null); then
    printf '%s\n' 'Test App starts an XCTest App host. Stop Run App and any manually launched PitPulse/F1Companion first, then retry.' >&2
    exit 1
fi

cd "$project"
# Build/test products stay separate from the running Taskdeck App bundle.
exec /usr/bin/xcodebuild \
    -workspace PitPulse.xcworkspace \
    -scheme PitPulseDesktop \
    -destination "platform=macOS,arch=$(uname -m)" \
    -configuration "$configuration" \
    -derivedDataPath "$HOME/Library/Caches/PitPulse/XcodeDevelopment" \
    "$action"
