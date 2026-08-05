# arcana-windows → arcana-macos — Port Status & Plan

Port of the WinUI 3 / .NET 10 Windows app to a Swift 6 / SwiftUI **macOS** app.
Strategy (from the architecture survey): ~70% of the skeleton transplants directly from
`arcana-ios` (Clean Architecture layers, MVVM Input/Output/Effect, swift-dependencies DI,
type-safe NavGraph, SwiftData, offline-first, Swift Testing); the net-new macOS work is the
CRDT sync engine, the plugin system, and the desktop shell.

## ✅ P0 — Scaffold (done)
- SPM package (`Package.swift`, swift-tools 6.0, `.macOS(.v15)`), library `ArcanaKit` +
  executable `ArcanaMacApp` + test target.
- Dependencies resolved: swift-dependencies, Alamofire, LRUCache.
- macOS App shell: `ArcanaApp` (WindowGroup + Settings scene) launched by a one-line executable.
- **`swift build` + `swift test` green.**

## ✅ P1 — Swift Arcana base transplanted (done)
- Ported the four layers from `arcana-ios` (38 Swift files): ArcanaCore / ArcanaDomain /
  ArcanaData / ArcanaPresentation, unchanged where platform-agnostic.
- macOS adaptation of the iOS-only presentation APIs:
  - `Compat.swift` shims: `UIKeyboardType`, `navigationBarTitleDisplayMode`, `keyboardType`,
    `autocapitalization`, and cross-platform `Color.arcanaSystemGray6/.arcanaSystemBackground`.
  - Source rewrites: `.navigationBar{Leading,Trailing}` → `.cancellationAction/.primaryAction`,
    `Color(.systemGray6/.systemBackground)` → the cross-platform helpers, `.fullScreenCover` → `.sheet`.
- Concurrency touch-ups to build on the Swift 6.3 compiler: `@MainActor` on the SwiftData DAO /
  offline-first repository, `Sendable` on the domain/data protocols, `nonisolated(unsafe)` on the
  DI singletons and `AppConfiguration.shared`.

## 🟡 P1.5 — Swift 6 strict-concurrency uplift (~90% done)
Turning `.swiftLanguageMode(.v6)` on took the diagnostics from ~90 to ~26. The systematic
fixes are **applied and retained** (they are also valid in v5, so nothing is lost):
- `ApiService` → an **`actor`** (it holds a non-Sendable Alamofire `Session`).
- Domain/data protocols → **`Sendable`** (`UserService`, `UserRepository`, `AnalyticsTracker`,
  `UserLocalDao`, `UserRemoteDao`); value type `PaginatedResult<T: Sendable>: Sendable`.
- SwiftData DAO / offline-first repository → **`@MainActor`**.
- DI globals → **`nonisolated(unsafe)`**; test/preview doubles → `final` + `@unchecked Sendable`.

The build mode stays **`.v5`** so it compiles today; the last three sites need per-call
restructuring to reach full strict `.v6` (each is localized):
1. **`ApiService`** — the per-request `[String: Any]` Alamofire parameter dictionaries are
   inherently non-Sendable. Fix: typed `Encodable & Sendable` param structs (or inline GET
   query into the URL) instead of `[String: Any]`.
2. **`PersistentAnalyticsTracker`** — `sending 'context' / 'params' / 'events'` across the
   inner `Task { @MainActor in … }`. Fix: `@MainActor`-isolate the tracker (its SwiftData
   `context` is already `@MainActor`) and change the protocol's `params: [String: Any]` to
   `[String: String]` (Sendable analytics metadata).
3. **`ArcanaCore/Common/Extensions.swift`** — one `sending 'value'` in a generic helper.

Then flip `Package.swift` back to `.swiftLanguageMode(.v6)` and confirm zero diagnostics.

## ⏳ P2 — CRDT sync engine (`ArcanaSync`)
Port `Arcana.Sync` from Windows: `VectorClock`, `LWWRegister`, `MVRegister`, `ConflictResolver`,
`SyncableEntity`, `SyncService` (actor), layered on SwiftData. Replaces the iOS base's weaker
timestamp-LWW queue with proper vector-clock CRDT.

## ⏳ P3 — Plugin system (`ArcanaPluginContracts` + `ArcanaPlugins`)
Port the VS Code-style contribution model: `ArcanaPlugin` protocol, `PluginManifest`,
activation events, Menu/View/Command registries, MessageBus/EventAggregator, permissions, health,
version store. **macOS forbids Windows-style DLL hot-loading**, so plugins are static Swift-package
modules conforming to `ArcanaPlugin`, self-registering at launch. Reference plugin: port `FlowChartModule`.

## ⏳ P4 — Desktop shell (macOS-native)
`WindowGroup` + `MenuBarExtra` + `Settings` + `.commands` main menu, `NavigationSplitView` sidebar,
multi-window / document tabs / tear-off windows, ThemeService. Wire plugin-contributed menus/views/routes in.

## ⏳ P5 — Feature modules + RBAC/Identity
Port Customer / Order / Product CRUD (as built-in plugins) + Identity/Role/Permission/Audit +
Auth/Token/PasswordHasher (Keychain for secrets).

## ⏳ P6 — CI + docs
- **Jenkins `macos-app-pipeline-mb`** at https://arcana.boo/jenkins/ (multibranch), building with
  `swift build`/`swift test`, gated on **SonarQube** and **arch-qube** both passing.
- release-please, renovate, ARCHITECTURE.md — mirroring the arcana-windows CI/docs conventions.

## Notes
- Toolchain in use: Swift 6.3.3 / Xcode 26.6 (the machine's latest; "Swift 6.4" tracks the same 6.x line).
- A double-clickable `.app` bundle needs an Xcode project (added in P4/P6); today the package builds and
  `swift run` launches it for development.
