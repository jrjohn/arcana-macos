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

## ✅ P4 — Desktop shell (`ArcanaShell`) (done)
The SwiftUI macOS shell, ported from the Windows MainWindow/App composition, as its own
target (`.swiftLanguageMode(.v6)`). `swift build` + the **9-test `ArcanaShellTests` suite are green**.
- **Chrome** — `NavigationSplitView` sidebar (built-in nav + plugin `FunctionTree` items) +
  a document **tab strip** (single- vs multi-instance, close, back/forward) + a status bar
  (message / online / live clock); `MenuBarExtra`; a `Settings` scene (theme + language).
- **Dynamic main menu** — `.commands` builds a menu from the plugin-contributed `MenuItemDefinition`s
  via `MenuTree` (`.mainMenu` roots + `parentId` nesting, ordered), dispatching `command` ids
  through the `CommandRegistry`.
- **View resolution** — a `ViewFactoryRegistry` replaces the Windows XAML type resolver: plugins
  (compiled-in) register a SwiftUI view factory per view id; the shell resolves tabs through it.
- **Navigation** — plugin commands publish `NavigationRequested` on the message bus; the shell
  subscribes and opens the target tab (the async handler makes it deterministic).
- **Composition root** — `CompositionRoot.makeShell()` builds the `PluginManager`, registers the
  built-in plugins (`CoreMenuPlugin` chrome + `CustomerModulePlugin`), and wires view factories.
- **Theme + localization** — `@Observable` `ThemeStore` (`.preferredColorScheme` + `.tint`) and
  `LocalizationStore` (zh-TW / en-US / ja-JP), persisted via `AppSettings` (UserDefaults).
- The executable (`ArcanaMacApp`) now launches `ArcanaShellApp`.
- **Deferred to P5**: real feature views (placeholders today); tear-off/floating document windows.

## ✅ P5 — Feature modules + RBAC/Identity (`ArcanaModel`) (done)
The domain + identity + auth layer, ported to SwiftData/CryptoKit as its own target
(`.swiftLanguageMode(.v6)`). `swift build` + the **13-test `ArcanaModelTests` suite are green**.
- **Foundation** — `AppError`/`ErrorCode`, `AppResult`, `PageRequest`/`PagedResult`.
- **Business entities** (SwiftData `@Model`, `Decimal` money) — `Customer`, `Product` /
  `ProductCategory`, `Order` / `OrderItem` with `calculateTotals()` and the computed `lineTotal`;
  every entity carries the audit / soft-delete / sync field groups.
- **Domain services** — `CustomerService` / `ProductService` / `OrderService` over `ModelContext`,
  returning `AppResult`, honoring soft-delete + `isPendingSync`, with order-number generation,
  line-number assignment, and totals.
- **Identity** — `User` / `Role` / `AppPermission` / `UserRole` / `RolePermission` /
  `UserPermission` / `AuditLog`, plus the `SystemRoles` / `SystemPermissions` catalog and an
  idempotent first-launch `IdentitySeed` (admin + Administrator role + all permissions).
- **Auth** — `PasswordHasher` (PBKDF2-SHA256, 100k iterations, `version:iterations:salt:hash`
  format via CommonCrypto), `TokenService` (HMAC-SHA256 via CryptoKit, key from **Keychain**),
  `CurrentUserService` (`@Observable` session), and the pure `PermissionResolver` (role union
  then direct grant/deny, expiry + soft-delete filtered).
- **Shell integration** — the shell now hosts a **real SwiftData-backed `CustomerListView`**
  (`@Query` + inline create via `CustomerService`); `CompositionRoot` builds + seeds the
  `ModelContainer` and the window carries `.modelContainer`.
- **Deferred** (per the spec's first-pass scope): refresh-token rotation / lockout / reset,
  Order/Product detail editors, DB encryption; ArcanaSync wiring (the `Syncable` fields exist).
- **Note on SwiftData**: `isDeleted` collides with `NSManagedObject.isDeleted` (→ crash) so the
  field is `isSoftDeleted`; the test suite shares one in-memory container (per-test containers
  race CoreData teardown → SIGTRAP).

## ✅ P6 — CI + docs (done)
The CI artifacts are in-repo and verified locally; the pipeline runs on the **Mac mini agent**
(SwiftUI/SwiftData/AppKit need a real macOS toolchain), so it does a full `swift build` / `swift test`.
- **`Jenkinsfile`** — declarative pipeline, `agent { label 'macmini' }`, stages: Checkout →
  Build → Test + Coverage → **arch-qube** (selftest then enforce) → **SonarQube analysis** →
  **Quality Gate** (`waitForQualityGate abortPipeline: true`). Job name: `macos-app-pipeline-mb`.
- **`scripts/arch-qube.sh`** — architecture conformance gate (module dependency direction);
  100%-or-fail, with a `selftest` that proves it isn't blind. **Passes: 0 violations.**
- **`scripts/coverage.sh`** — `swift test --enable-code-coverage` → `xcrun llvm-cov export`
  → `coverage.lcov`. **Verified: 55 tests green, lcov produced.**
- **`sonar-project.properties`** — Swift analysis + lcov coverage import.
- **`ARCHITECTURE.md`** — module graph + the dependency rules arch-qube enforces.
- **`renovate.json`** (SPM updates) + **release-please** config/manifest + `VERSION`.
- **Live & green** — the multibranch job `macos-app-pipeline-mb` is registered on
  https://arcana.boo/jenkins/ and building `main`. Build #5: `swift build` + **90 tests** +
  arch-qube (0 violations) + SonarQube **QUALITY GATE PASSED** (coverage **87.7%** over the
  tested product modules, ratings A/A/A). SonarQube runs via the `sonarsource/sonar-scanner-cli`
  Docker image on the built-in node (`devops_default` → `sonarqube:9000`), `sonar.qualitygate.wait`
  blocking the build on the gate.

## Notes
- Toolchain in use: Swift 6.3.3 / Xcode 26.6 (the machine's latest; "Swift 6.4" tracks the same 6.x line).
- A double-clickable `.app` bundle needs an Xcode project (added in P4/P6); today the package builds and
  `swift run` launches it for development.
