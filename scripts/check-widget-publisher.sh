#!/bin/bash
set -euo pipefail

# Runs the SharedData widget publisher tests without launching/stopping PitPulse.
root="$(cd "$(dirname "$0")/.." && pwd)"
exec /usr/bin/swift test \
    --package-path "$root/Packages/SharedData" \
    --filter WidgetSnapshotPublisherTests
