# PitPulse — F1 Companion

Self-hosted F1 companion consisting of a Rust API/data service, a native macOS Menu Bar + Notch app, and an iOS 26+ companion with Live Activity / Dynamic Island.

- Architecture: `F1-Companion-Architecture.md`
- Task status board: [`docs/tasks/index.html`](docs/tasks/index.html) · [JSON data](docs/tasks/tasks.json) · [preview/update guide](docs/tasks/README.md)
- Implementation plan: [`implementation-sequence.md`](implementation-sequence.md)
- Independent helmet / team-logo collection task: [`docs/tasks/T03-motorsport-assets.md`](docs/tasks/T03-motorsport-assets.md)

## Repository layout

```
PitPulse.xcworkspace            # Xcode entry point: app project + three local packages
PitPulse.xcodeproj              # single app project, committed as source of truth
Packages/
├── PitPulseShared/             # pure value contracts shared by everything
├── PitPulseData/               # networking / storage / live stream / platform-agnostic services
└── PitPulseComponents/         # value-only SwiftUI atoms
macos/                          # macOS app sources (Desktop target)
ios/                            # iOS app + widget extension sources (Mobile target)
server/                         # Rust API / data service
docs/                           # task board, acceptance evidence, architecture notes
scripts/                        # build / run helpers used by Taskdeck
```

## Xcode workspace and module conventions

**Open `PitPulse.xcworkspace`, not an individual project or package.** It manages the single app project and the three packages together.

### Targets

| Target | Kind | Responsibility |
| --- | --- | --- |
| `PitPulseDesktop` | macOS app | Menu bar, Notch / Live Island, map, settings |
| `PitPulseMobile` | iOS app | Calendar, Live, settings |
| `PitPulseLiveActivity` | iOS app extension | WidgetKit / ActivityKit Live Activity (Dynamic Island, lock screen) |
| `PitPulseDesktopTests` / `PitPulseDesktopUITests` / `PitPulseMobileTests` | test bundles | unit / UI acceptance |

### Packages (three modules, package name = module name)

| Package / module | May depend on | Must not depend on |
| --- | --- | --- |
| `PitPulseShared` | Foundation | `PitPulseData`, `PitPulseComponents`, app targets |
| `PitPulseData` | `PitPulseShared` | `PitPulseComponents`, app targets |
| `PitPulseComponents` | `PitPulseShared` | `PitPulseData`, app targets, AppKit / UIKit window APIs |

Rules:

1. Each package lives under `Packages/<Name>/` and has its own `Package.swift`. The package `name`, its single library product, and its target (module) name must all be identical — no umbrella package containing differently named modules.
2. Dependency direction is `PitPulseShared ← PitPulseData` and `PitPulseShared ← PitPulseComponents`. `PitPulseComponents` intentionally does not depend on `PitPulseData`, so widget / watch targets never link the network stack.
3. Packages never import app code. App-specific types (`AppModel`, `LiveIsland`, view controllers) stay in the app targets.
4. Cross-module symbols are `public`; keep platform-only code behind the app target or `#if os(...)`, not in shared modules.
5. New module: create `Packages/<Name>/Sources/<Name>/` with its `Package.swift`, then add the local package to `PitPulse.xcworkspace` / the target in Xcode and declare the product dependency.

### Naming and icons

- App display name is **PitPulse** on both platforms (`CFBundleDisplayName` / `CFBundleName`).
- Both app targets share `macos/Resources/AppIcon.icon` (Icon Composer) via `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
- macOS keeps bundle id `com.pitpulse.F1Companion` for Keychain / preferences compatibility; iOS uses `com.pitpulse.mobile`.
- Scheme names: `PitPulseDesktop`, `PitPulseMobile`, `PitPulseLiveActivity`, `PitPulseLiveAcceptance`.
- Run the **`PitPulseMobile` app scheme**; the widget extension is embedded and is not a standalone runnable app.

### Project files and signing

`PitPulse.xcodeproj` is committed and is the source of truth: edit targets, schemes and signing in Xcode. **Do not regenerate or overwrite the project** — the Development Team / provisioning settings live in the project file, and regenerating wipes them. If a structural change ever needs scripted generation, preserve the existing `DEVELOPMENT_TEAM` / provisioning values from the project first.

Build and test through the workspace:

```sh
# macOS app / unit test compile
xcodebuild -workspace PitPulse.xcworkspace -scheme PitPulseDesktop -destination 'platform=macOS' build
xcodebuild -workspace PitPulse.xcworkspace -scheme PitPulseDesktop -destination 'platform=macOS' build-for-testing

# iOS app / tests
xcodebuild -workspace PitPulse.xcworkspace -scheme PitPulseMobile -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace PitPulse.xcworkspace -scheme PitPulseMobile -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO test
```

## Server address

The client accepts **any host / IP and both `http` and `https`**; a bare address defaults to `http` (self-hosted deployments are commonly reached by LAN IP). Use `https://…` explicitly when TLS terminates in front of the server. Public deployments should still prefer HTTPS + Bearer Token.

## Current scope

Shipped locally: Rust service (calendar / results / standings / live F1 + opt-in WEC), macOS Menu Bar + Notch Live Island, and iOS 26+ app with calendar, live timing and Dynamic Island Live Activity. The iOS Live Activity is verified in the simulator; real-device Dynamic Island acceptance and watchOS / Watch Widget remain open.

See `server/README.md` for server build, test, run and deployment guidance.

## Local development with Taskdeck

`taskdeck.yaml` is the command source of truth for the `PitPulse` session. Register it on a new machine with `taskdeck register --session PitPulse`, and run `taskdeck update --session PitPulse` after editing the file.

Tasks: `Run Server`, `Run App`, `Build App`, `Build App Tests`, `Build App Release`, `Build iOS`, `Test iOS`, `Test Server`, `Check Server Format`, `Lint Server`, `Check Task Report`. Start one explicitly:

```sh
taskdeck start --session PitPulse --task "Run Server"
taskdeck start --session PitPulse --task "Run App"
taskdeck status --session PitPulse
taskdeck restart --session PitPulse --task "Run Server"
taskdeck stop --session PitPulse
```

`Run Server` uses `scripts/run-server.py` and the real F1 provider. Local configuration is read from `~/Library/Application Support/PitPulse/server/environment.json` when present (string `F1_COMPANION_*` / `F1_LIVE_ACCESS_TOKEN` values only); Mapbox's public token is read from `~/Library/Application Support/PitPulse/mapbox-public-token`. Keep these local files private and outside Git. The default database also lives in that user directory.

`Run App` uses `scripts/run-app.sh`, builds the Release app into `~/Library/Caches/PitPulse/Xcode`, and connects to `http://127.0.0.1:38701`. Starting the App does not require the server to be ready; the existing retry path reconnects. Tasks start manually (`auto_start: false`). If the upstream has ended or stopped updating, the App continues to show its real stale/disconnected state.

`Build App Tests` compiles macOS tests without launching a host. `Test Server` / `Test iOS` run their suites. Run Cargo tasks sequentially and serialize Xcode development tasks; routine agent work follows the Taskdeck-first rules in `AGENTS.md`.
