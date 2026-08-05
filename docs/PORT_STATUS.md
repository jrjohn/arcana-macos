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

## ✅ P1.5 — Swift 6 strict-concurrency uplift (done)
`Package.swift` runs both targets in **`.swiftLanguageMode(.v6)`**; `swift build` and
`swift test` are **green with zero concurrency diagnostics** (was ~90 errors at the start).
The systematic fixes:
- `ApiService` → an **`actor`** (it holds a non-Sendable Alamofire `Session`); its request
  bodies/queries are now typed **`Encodable & Sendable`** structs (`UsersQuery`, `UserPayload`,
  `UserPatchPayload`) fed to Alamofire's `Encodable` overload — no more `[String: Any]`.
- Domain/data protocols → **`Sendable`** (`UserService`, `UserRepository`, `AnalyticsTracker`,
  `UserLocalDao`, `UserRemoteDao`); value type `PaginatedResult<T: Sendable>: Sendable`.
- SwiftData DAO / offline-first repository → **`@MainActor`**; the analytics query helpers
  (which hand back non-Sendable `@Model` rows) → **`@MainActor`**, no continuation hop.
- Analytics params typed **`[String: any Sendable]`** (Sendable, so they cross into the
  tracker's `@MainActor` persistence `Task`; `Int`/`String`/`Bool` call sites are unchanged).
- One generic `Publisher.async()` helper constrained to **`Output: Sendable`**.
- DI globals → **`nonisolated(unsafe)`**; test/preview doubles → `final` + `@unchecked Sendable`.

## ✅ P2 — CRDT sync engine (`ArcanaSync`) (done)
A faithful Swift port of the Windows `Arcana.Sync` assembly, as its **own dependency-free SPM
target** (`Sources/ArcanaSync`, `.swiftLanguageMode(.v6)`), mirroring the .NET assembly split.
`swift build` + the **18-test `ArcanaSyncTests` suite are green**.
- **`VectorClock`** — immutable value type; `incremented` / `merged` (component-wise max) /
  `relation(to:)` → `CausalRelation` (after / before / concurrent / equal); `Comparable` by
  causality; JSON `serialized()` / `deserialize` matching the C# wire form.
- **`LWWRegister<Value>`** + **`LWWMap`** — last-writer-wins with node-id tie-break; the map
  does field-level merges so concurrent edits to different fields both survive. C#'s `object?`
  field value becomes a closed, `Sendable`/`Codable` `SyncValue` enum.
- **`MVRegister<Value>`** — keeps all causally-maximal concurrent values, drops dominated ones,
  `resolve` collapses them.
- **`ConflictResolver`** — causal short-circuits, then a per-type strategy registry
  (`lastWriterWins` / `firstWriterWins` / `fieldLevelMerge` / `keepBoth` / `custom`) with a
  merged-and-bumped clock. C#'s property reflection is replaced by the `SyncResolvable` protocol
  (`entityId` + optional `fieldLevelMerged`).
- **`SyncableEntity`** (+ `SyncMetadata`, `SyncConflictRecord`), **`SyncService`** protocol with
  `SyncState` / `SyncOperationType` and `AsyncStream` progress (the idiomatic swap for C# events).

**Next:** wire the offline-first repository's pending-change queue onto `ArcanaSync` (replacing the
iOS base's timestamp-LWW), and add a concrete `SyncService` actor over SwiftData.

## ✅ P3 — Plugin system (`ArcanaPluginContracts` + `ArcanaPlugins`) (done)
A faithful Swift port of the Windows `Arcana.Plugins.Contracts` + `Arcana.Plugins` assemblies,
as **two dependency-free SPM targets** (`.swiftLanguageMode(.v6)`) mirroring the .NET split.
`swift build` + the **14-test `ArcanaPluginsTests` suite are green**.
- **Contracts** — `ArcanaPlugin` (@MainActor) + `PluginContext`; the `PluginType` (18-case)
  taxonomy + `PluginState`; contribution defs (`MenuItemDefinition`/12 `MenuLocation`,
  `ViewDefinition`/5 `ViewType`, `CommandDefinition`); registry protocols; `MessageBus` /
  `EventAggregator` / `SharedStateStore`; `PluginPermission` as a 20-bit **`OptionSet`** with
  the composites; `HealthState` / `PluginHealthStatus`; the declarative `PluginManifest` +
  `ManifestContributions`; `ActivationEvents` parsing; and the id-regex `ContributionValidators`.
- **Runtime** — lock-guarded `Sendable` service impls (menu/view/command registries, a typed
  `MessageBus` with request/response, `EventAggregator`, `SharedStateStore`, permission
  manager); `ArcanaPluginBase` with auto-tracked `register*` helpers; and a `PluginManager`
  that does **dependency-ordered activation** (topological sort, cycle detection),
  **activation-event gating**, subscription teardown on deactivate, and a `PluginStateChange`
  `AsyncStream`. Reference plugin: **`CustomerModulePlugin`** (programmatic view/menu/command).
- **Isolation model** — plugin-facing surface is `@MainActor` (UI contributions); services are
  lock-guarded `@unchecked Sendable`, so background code can still publish to the bus.
- **Deliberately out of scope** (macOS has no equivalent / host concerns): dynamic
  `AssemblyLoadContext` load-unload, ZIP install/upgrade/rollback, the EF version store, the
  localization file loader, and the periodic health `Timer`. Plugins are static Swift modules
  that self-register at launch, exactly as the roadmap called for.

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
