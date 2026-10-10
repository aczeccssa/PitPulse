# OpenNook macOS spike

**Observed:** 2026-10-10 (Asia/Shanghai), macOS 26.5 / Xcode 26.6. **Pinned revision:** `2b50b5c3a99df8914e25e199d29bf7aa505f7a59`.

The independent prototype is at `spikes/opennook-spike`. Its Swift package declares macOS 15.0 and pins OpenNook to the revision above. It imports `Nook` through the `NookApp` product re-export, keeps one `@main` SwiftUI app entry, and declares a separate `MenuBarExtra`; it does not call `NookApp.main()` or link OpenNook into the production app. `swift build --package-path spikes/opennook-spike` succeeded.

## Runtime observations

- Built-in Retina display with a notch: controller reported `expanded · notch · Built-in Retina Display`.
- External HUAWEI display without a notch: controller reported `expanded · floating · HUAWEI AD80HW`; the panel rendered legible white text on its dark surface. A cropped screenshot is saved as [opennook-spike.png](acceptance/assets/opennook-spike.png).
- Compact mode reported `compact` on the built-in display.
- Hide destroyed the surface window and reported `hidden · notch · 无窗口`.
- The controller's Quit action ended the spike process.
- Two displays were detected. The controller's display-selection buttons moved the surface between the built-in and external displays.

The same `App` declares both `WindowGroup` and `MenuBarExtra`, and the package builds. The status item itself was not opened as part of this run, so interactive menu coexistence remains unverified. The main app remains untouched by the spike and keeps its macOS 14 deployment target.

## Failure and limits

The first local package build failed because the prototype folder name collided with the remote package identity `opennook`. Renaming the local directory to `spikes/opennook-spike` resolved the collision without changing OpenNook's package manifest. This run validates the current hardware and OS only; it does not establish behavior on macOS 15 or on older Macs without a notch.
