# arcana-windows → arcana-macos — Full Feature Checklist

Every feature area of the Windows app, with its macOS port status.

**Legend:** ✅ working (real, usable) · 🟡 backend/library done, **no UI wired** · ❌ not done / placeholder

> Bottom line: the **architecture** is ported in full (all layers, tested, CI-green), but most
> **feature UI** is not built yet. Only the shell + a basic Customers list are real; everything
> else is either a backend layer with no screen, or a placeholder.

---

## A. Architecture / Foundation
- ✅ SwiftData persistence + model container + seeding (identity)
- ✅ `Result`/`AppError`/`ErrorCode`, `PagedResult`/`PageRequest`
- ✅ Entity field groups: audit (created/modified), soft-delete, sync (SyncId/pending)
- 🟡 Repository pattern (via services; no explicit Unit-of-Work)
- 🟡 DI (swift-dependencies in ArcanaKit; shell uses manual composition root)
- ❌ `ConcurrencyAware` (RowVersion) optimistic concurrency
- ❌ Sample-data seeding (customers / products / orders)
- ❌ Global soft-delete query filter (currently per-query)
- ❌ DB encryption (SQLCipher)

## B. CRDT Sync Engine (`ArcanaSync`)
- ✅ `VectorClock` (causality, merge, compare)
- ✅ `LWWRegister` / `LWWMap` (field-level LWW)
- ✅ `MVRegister` (multi-value, conflict preserve/resolve)
- ✅ `ConflictResolver` (LWW / FWW / field-merge / keep-both / custom)
- ✅ `SyncableEntity` / `SyncMetadata` / `SyncConflictRecord`
- ✅ `SyncService` **protocol** + state/operation enums + AsyncStream events
- ❌ **Concrete `SyncService` (actual background sync loop over SwiftData)**
- ❌ **Wired into the app** — nothing actually syncs
- ❌ `SyncQueueItem` persistence + pending-change draining
- ❌ Networking / remote sync transport
- ❌ Conflict-resolution UI

## C. Plugin System (`ArcanaPluginContracts` + `ArcanaPlugins`)
- ✅ `ArcanaPlugin` contract + `PluginContext`
- ✅ `PluginType` (18-case taxonomy)
- ✅ Contribution defs: `MenuItemDefinition` (12 locations), `ViewDefinition` (5 types), `CommandDefinition`
- ✅ Registries: Menu / View / Command
- ✅ `MessageBus` (pub/sub + request/response), `EventAggregator`, `SharedStateStore`
- ✅ `PluginPermission` (20-bit OptionSet) + composites + permission manager
- ✅ Declarative `PluginManifest` + contributions + `ActivationEvents` + validators
- ✅ `PluginManager`: register / activate / dependency-order / activation-event gating / state stream
- ✅ Reference plugin: `CustomerModulePlugin` (programmatic view/menu/command)
- 🟡 Health types (`HealthState`, `PluginHealthCheck`) — no monitor/timer
- ❌ **Dynamic loading** (DLL/assembly hot-load) — macOS forbids; static modules by design
- ❌ Plugin install / upgrade / rollback (ZIP packages)
- ❌ Plugin version store (DB) + version history
- ❌ Periodic health monitor
- ❌ Runtime permission **enforcement** (sandbox) — types exist, not enforced
- ❌ **Plugin management UI** (install / enable / disable / permissions) — only a read-only list
- ❌ The other 17 plugin types actually implemented as plugins (only Module exists)
- ❌ Auth plugins (OAuth / OIDC / LDAP / SAML / SSO / MFA)
- ❌ Lazy contribution loading, hot-reload, localization-per-plugin loading

## D. Desktop Shell (`ArcanaShell`)
- ✅ Window (`WindowGroup`) + sidebar (`NavigationSplitView`)
- ✅ Document tabs (open / close / select / single-instance dedup)
- ✅ Dynamic main menu built from plugin contributions (`.commands`)
- ✅ `MenuBarExtra` (minimal), `Settings` scene
- ✅ Status bar (message / online / live clock)
- ✅ `ViewFactoryRegistry` (id → SwiftUI view)
- ✅ Command→bus→tab navigation
- 🟡 Back/forward nav (in `ShellModel`, not surfaced as UI buttons)
- 🟡 Theme (6 of 10; no runtime brush override — SwiftUI environment-driven)
- 🟡 Localization (shell strings zh/en/ja; no per-plugin l10n file loading)
- 🟡 FunctionTree sidebar contributions (model supports; no plugin uses it)
- 🟡 QuickAccess / ModuleQuickAccess menus (model supports; not rendered as the tab "+" menu)
- ❌ **Nested module tabs (MDI)** — e.g. Order module's inner tab strip
- ❌ **Pop-out / floating document windows + dock-back**
- ❌ **Multi-window**
- ❌ Toolbar surface
- ❌ Context menus (tab / item)
- ❌ Search box
- ❌ Sidebar / status-bar toggle menu items
- ❌ Keyboard shortcuts bound from menu `Shortcut` strings

## E. Feature Modules

### Customer
- ✅ List (SwiftData `@Query`) + inline add
- ❌ **Detail / edit page (master-detail)**
- ❌ Search UI (service has search), paging UI, edit, delete

### Product
- 🟡 Domain model + `ProductService` (create / get / page) — backend only
- ❌ List UI (placeholder), detail/edit, category management, stock management

### Order — the Windows flagship (master-detail)
- ✅ Domain + `OrderService`: `calculateTotals()`, order-number gen, line items, status change (backend, tested)
- ❌ **List page**
- ❌ **Detail page (master-detail)** + order-item editing
- ❌ **Input / Output / Effect ViewModel** (pattern known; not built for macOS)
- 🟡 Status workflow / payment status+method (service supports; no UI)
- ❌ Nested tabs + pop-out floating windows

## F. Identity / RBAC / Auth (`ArcanaModel`)
- ✅ Entities: User / Role / AppPermission / UserRole / RolePermission / UserPermission / AuditLog
- ✅ `SystemRoles` / `SystemPermissions` catalog + idempotent `IdentitySeed` (admin)
- ✅ `PasswordHasher` (PBKDF2-SHA256, compatible format)
- ✅ `TokenService` (HMAC-SHA256, key from Keychain)
- ✅ `CurrentUserService` (observable session + gating helpers)
- ✅ `PermissionResolver` (role union → direct grant/deny, expiry + soft-delete filtered)
- 🟡 Cohesive `AuthService.authenticate` flow (primitives exist; not assembled into one login flow + audit)
- ❌ **Login screen**
- ❌ **User / Role / Permission management UI**
- ❌ **Audit-log viewer**
- ❌ **Permission gating in the UI** (hide / disable controls by permission)
- ❌ Account lockout (5-strike / 15-min), refresh-token rotation, password reset
- ❌ MFA, external auth providers

## G. Cross-cutting UI Services
- 🟡 Navigation (basic tab nav; no `ShowDialog`, no within-tab nav)
- ❌ Dialogs (info / warning / error / input / confirm)
- ❌ File pickers (open / save) — `NSOpenPanel` / `.fileImporter`
- ❌ Progress dialogs
- ❌ Plugin-contributed status-bar items
- ❌ Notifications
- ❌ Clipboard access
- ❌ Open-URL / launch external (help docs)

## H. Packaging / Distribution
- ✅ SPM executable (`ArcanaMacApp` → `ArcanaShellApp`)
- 🟡 Ad-hoc `.app` bundle (`.build/Arcana.app`, unsigned, for local verify)
- ❌ Xcode project (proper `.app`, entitlements, Sparkle/updates)
- ❌ Code-signing / notarization / DMG

## I. CI / DevOps
- ✅ Jenkins `macos-app-pipeline-mb` (Mac mini agent)
- ✅ arch-qube (architecture conformance gate)
- ✅ SonarQube analysis + quality gate (coverage 87.7%)
- ✅ Coverage export (lcov → Sonar generic)
- ✅ renovate + release-please config
- ❌ Signing / notarization in CI, artifact distribution

---

## Rough completeness

| Area | Status |
|---|---|
| Architecture / layers | ~95% (foundation solid) |
| CRDT engine (library) | ~90% built · **0% wired into app** |
| Plugin system (core) | ~80% built · management/dynamic/enforcement missing |
| Desktop shell chrome | ~70% (no MDI / pop-out / multi-window) |
| **Feature UI (Customer/Product/Order/Reports)** | **~5%** (only a basic Customers list) |
| Identity/RBAC/Auth backend | ~85% · **UI 0%** |
| Cross-cutting UI services | ~10% |
| Packaging / signing | ~15% |

**One line:** the skeleton and all backend layers are here and tested; the **operable feature
screens** (Orders master-detail, product/customer editors, login + RBAC admin, live sync) are
the large remaining body of work.
