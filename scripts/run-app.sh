#!/bin/bash
set -euo pipefail

project="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="$HOME/Library/Caches/PitPulse/Xcode"
app="$derived_data/Build/Products/Release/PitPulse.app"
widget="$app/Contents/PlugIns/PitPulseWidgets.appex"
check_only=false
if [[ "${1:-}" == --check ]]; then
    check_only=true
    shift
fi
# Never build over the managed runtime bundle or launch a competing main App.
if /usr/bin/pgrep -x PitPulse >/dev/null || /usr/bin/pgrep -x F1Companion >/dev/null; then
    printf '%s\n' 'PitPulse is already running. Stop only Run App before building or launching this runtime bundle.' >&2
    exit 1
fi
cd "$project"

printf '%s\n' 'Building PitPulseDesktop Release, including the native Widget extension…'
/usr/bin/xcodebuild -quiet \
    -workspace PitPulse.xcworkspace \
    -scheme PitPulseDesktop \
    -configuration Release \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$derived_data" build

[[ -x "$app/Contents/MacOS/PitPulse" && -d "$widget" ]] || {
    printf '%s\n' 'Build is missing the PitPulse executable or embedded PitPulseWidgets.appex.' >&2
    exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$widget/Contents/Info.plist")" == com.apple.widgetkit-extension ]] || {
    printf '%s\n' 'Embedded extension is not a WidgetKit extension.' >&2
    exit 1
}
/usr/bin/codesign --verify --deep --strict "$app"
printf '%s\n' 'Verified Release app and embedded WidgetKit extension.'
if "$check_only"; then
    exit 0
fi

# Register the stable runtime bundle for Widget discovery and desktop deep links.
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$app"
/usr/bin/pluginkit -a "$widget"
printf '%s\n' 'Registered PitPulse and its native Widget extension.'

# The task YAML owns the optional local-server override; otherwise retain App preferences.
if [[ -n "${PITPULSE_SERVER_URL:-}" ]]; then
    set -- -serverAddress "$PITPULSE_SERVER_URL" "$@"
fi
printf '%s\n' 'Starting PitPulse Release in the foreground under Taskdeck.'
exec "$app/Contents/MacOS/PitPulse" "$@"
