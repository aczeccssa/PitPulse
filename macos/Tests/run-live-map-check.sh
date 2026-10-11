#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/pitpulse-map-check.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
awk '/^struct LiveTelemetryView: View/ {exit} {print}' "$repo_dir/macos/Features/Maps/LiveExtras.swift" > "$check_dir/RadioPlayer.swift"
awk '/^struct MapView: NSViewRepresentable/ {exit} {print}' "$repo_dir/macos/Features/Maps/MapView.swift" > "$check_dir/MapStore.swift"
swiftc -parse-as-library "$repo_dir/macos/Core/APIClient/APIModels.swift" "$repo_dir/macos/Core/LiveStore/LiveModels.swift" "$check_dir/RadioPlayer.swift" "$check_dir/MapStore.swift" "$repo_dir/macos/Tests/live-map-check.swift" -o "$check_dir/check"
"$check_dir/check"
