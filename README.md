# PitPulse — F1 Companion

Self-hosted F1 companion consisting of a Rust API/data service, a native macOS Menu Bar + Notch app, and an iOS 26+ companion with Live Activity / Dynamic Island.

- Architecture: `F1-Companion-Architecture.md`
- Implementation plan: [`implementation-sequence.md`](implementation-sequence.md)

## Repository layout

```
PitPulse.xcworkspace            # Xcode entry point: Desktop + Mobile projects and shared packages
macos/
├── PitPulseDesktop.xcodeproj   # committed Desktop project (generated)
├── project.yml                 # XcodeGen source for the Desktop project
├── App/ Core/ Features/        # macOS Menu Bar + Notch sources
├── PitPulseWidgets/            # macOS WidgetKit extension
└── Tests/ UITests/
ios/
├── PitPulseMobile.xcodeproj    # committed Mobile project (generated)
├── project.yml                 # XcodeGen source for the Mobile project
├── PitPulseMobile/             # iOS sources: App/, Core/, Features/ (Calendar, Live, Settings)
├── PitPulseLiveActivity/       # Live Activity / Dynamic Island extension
└── PitPulseMobileTests/
Packages/
├── SharedData/                 # value contracts, API/storage/live services, widget cache bridge
└── SharedComponents/           # shared SwiftUI components and image assets
server/                         # Rust API / data service
scripts/                        # build / run helpers used by Taskdeck
```

## Xcode workspace and module conventions

**Open `PitPulse.xcworkspace`, not an individual project or package.** It contains two independent app projects and the shared packages they both link.

- `macos/PitPulseDesktop.xcodeproj` owns the macOS app, WidgetKit extension and macOS test bundles.
- `ios/PitPulseMobile.xcodeproj` owns the iOS app, Live Activity extension and iOS unit tests.
- The Desktop and Mobile projects do not depend on each other. Both link `SharedData` and `SharedComponents`.

### Targets

| Target | Kind | Responsibility |
| --- | --- | --- |
| `PitPulseDesktop` | macOS app | Menu bar, Notch / Live Island, map, settings |
| `PitPulseMobile` | iOS app | Calendar, Live, settings |
| `PitPulseLiveActivity` | iOS app extension | Shared ordinary widgets + ActivityKit Live Activity (Dynamic Island, lock screen) |
| `PitPulseWidgets` | macOS app extension | Native small / medium / large next-session, weekend and F1 timing widgets |
| `PitPulseDesktopTests` / `PitPulseDesktopUITests` / `PitPulseMobileTests` | test bundles | unit / UI acceptance |

### Packages (two shared modules, package name = module name)

| Package / module | May depend on | Must not depend on |
| --- | --- | --- |
| `SharedData` | Foundation, platform frameworks used by API/storage/live code | `SharedComponents`, app targets |
| `SharedComponents` | `SharedData`, SwiftUI, Foundation | Desktop / Mobile app targets |

Rules:

1. Each package lives under `Packages/<Name>/` and has its own `Package.swift`. The package `name`, its single library product, and its target (module) name must all be identical.
2. Dependency direction is `SharedData ← SharedComponents`. App targets may link either package; both Desktop and Mobile link both.
3. Packages never import app code. App-specific types (`AppModel`, `LiveIsland`, view controllers) stay in the app targets.
4. Cross-module symbols used by the app or extensions are `public`; keep platform-only code behind the app target or `#if os(...)`, not in shared modules.
5. New shared code belongs in one of these two packages. Create a new package only when it has an independent dependency or distribution boundary, then add it to `PitPulse.xcworkspace` and declare the product dependency in both project specs.
6. A project spec never references files from the other platform's project folder. Anything both apps need — code or resources such as the icon — lives in a shared package or a neutral top-level folder.
7. Keep every Swift file under 300 lines: one screen/page per file, one group of related components per file, and feature folders (`Features/<Feature>/`) instead of a flat directory. Split a large type across `Type+Area.swift` extensions rather than growing one file.

### Naming and icons

- App display name is **PitPulse** on both platforms (`CFBundleDisplayName` / `CFBundleName`).
- Both app targets share `Packages/SharedComponents/Resources/AppIcon.icon` (Icon Composer) via `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`; neither project reaches into the other project's folder. The package keeps this icon outside `Sources/` so SwiftPM does not bundle it into the library.
- macOS keeps bundle id `com.pitpulse.F1Companion` for Keychain / preferences compatibility; iOS uses `com.pitpulse.mobile`.
- Scheme names: `PitPulseDesktop`, `PitPulseMobile`, `PitPulseLiveActivity`, `PitPulseLiveAcceptance`.
- Run the **`PitPulseMobile` app scheme**; the widget extension is embedded and is not a standalone runnable app.

### Project files and signing

`macos/project.yml` and `ios/project.yml` are the source of truth for their projects. Edit the YAML, then regenerate the committed projects with XcodeGen:

```sh
xcodegen generate --spec macos/project.yml
xcodegen generate --spec ios/project.yml
```

The specs carry the signing configuration (`DEVELOPMENT_TEAM`, bundle IDs, entitlements, `CODE_SIGN_STYLE`), so a regeneration keeps local signing intact. Do not hand-edit the generated `.xcodeproj` files for structural changes; change the YAML instead and commit both the spec and the regenerated project.

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

Tasks currently registered by this configuration: `Run Live Replay`, `Run App`, `Check App Launcher`, `Build App`, `Build App Tests`, `Build App Release`, `Build iOS`, `Test iOS`, `Check Widget Publisher`, and `Connect Simulator Replay`. Start one explicitly:

```sh
taskdeck start --session PitPulse --task "Run Live Replay"
taskdeck start --session PitPulse --task "Run App"
taskdeck status --session PitPulse
taskdeck restart --session PitPulse --task "Run App"
taskdeck stop --session PitPulse --task "Run App"
```

`Run Live Replay` uses `scripts/run-live-replay.py` and the real F1 provider. Local configuration is read from `~/Library/Application Support/PitPulse/server/environment.json` when present (string `F1_COMPANION_*` / `F1_LIVE_ACCESS_TOKEN` values only); Mapbox's public token is read from `~/Library/Application Support/PitPulse/mapbox-public-token`. Keep these local files private and outside Git. The default database also lives in that user directory.

`Run App` directly invokes `scripts/run-app.sh` with Bash. It builds `PitPulseDesktop` Release for the host architecture into `~/Library/Caches/PitPulse/Xcode`, checks the embedded `PitPulseWidgets.appex` and the complete bundle signature, registers the App/deep links and Widget with LaunchServices/PlugInKit, then `exec`s the foreground App so Taskdeck owns its real PID. The App keeps its saved server preference; set `PITPULSE_SERVER_URL` in the task environment to override it for one run. Tokens remain in Keychain. The launcher refuses to build over a running main App; use a targeted `Run App` restart rather than launching a second instance. `Check App Launcher` runs the same build/signature checks without registering or starting the App, and likewise requires the main App to be stopped. Development/test builds use separate DerivedData. Server availability remains handled by the App's retry path; stale/disconnected upstream data is not replaced by replay. All tasks remain manual (`auto_start: false`).

`Build App Tests` compiles macOS tests without launching a host.

## VPS release pipeline

[Deployment acceptance](docs/acceptance/deployment.md) documents the versioned CI artifact, manual production approval, dedicated SSH key boundary, immutable release directories, SQLite backup/atomic systemd switch, HTTPS/SSE health checks and rollback. The active operator config is `/etc/pitpulse/config.toml`; bootstrap preserves an existing file and deploys never replace it, so manually enabled feature flags survive every release. CI builds the Linux x86-64 artifact; `.github/workflows/deploy.yml` is a manually dispatched `production` environment workflow that uses only repository-external GitHub Secrets. Cold start uses a new VPS SQLite DB, never the local WAL database. Configure the app with `https://pitpulse.lestere.bond` and its per-server Keychain Bearer token after the public site is accepted.

The repository contains keyless templates only. The user has added the DNS A record and approved the production rollout; see [deployment acceptance](docs/acceptance/deployment.md) for verification details and go-live checks. Do not store real tokens, SSH keys, SQLite databases or captured live-feed logs in Git or CI artifacts.
 `Test Server` / `Test iOS` run their suites. Run Cargo tasks sequentially and serialize Xcode development tasks; routine agent work follows the Taskdeck-first rules in `AGENTS.md`.
