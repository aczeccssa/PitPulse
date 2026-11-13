#!/bin/bash
set -euo pipefail

project="$(cd "$(dirname "$0")/.." && pwd)"
action="${1:-build}"
configuration="${2:-Debug}"
case "$action" in
    build|build-for-testing|test|test-navigation) ;;
    *) printf '%s\n' 'Expected build, build-for-testing, or test.' >&2; exit 2 ;;
esac
case "$configuration" in
    Debug|Release) ;;
    *) printf '%s\n' 'Expected Debug or Release configuration.' >&2; exit 2 ;;
esac

scheme="PitPulseMobile"
if [[ "$action" == test-navigation ]]; then
    action=test
    scheme=PitPulseMobileNavigation
fi
cd "$project"
destination="${PITPULSE_IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 16 Pro}"

exec /usr/bin/xcodebuild -quiet \
    -workspace PitPulse.xcworkspace \
    -scheme "$scheme" \
    -destination "$destination" \
    -configuration "$configuration" \
    -derivedDataPath "${PITPULSE_IOS_DERIVED_DATA:-$HOME/Library/Caches/PitPulse/XcodeIOSVerification}" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_IDENTITY=- \
    "$action"
