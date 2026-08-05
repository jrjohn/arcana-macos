# Architecture

`arcana-macos` is the Swift 6 / SwiftUI macOS port of
[`arcana-windows`](https://github.com/jrjohn/arcana-windows) (WinUI 3 / .NET 10). It is a
Local-First, Plugin-Everything desktop app built as a Swift Package with a strict module
dependency direction, enforced in CI by [`scripts/arch-qube.sh`](scripts/arch-qube.sh).

## Module graph

```
            ┌──────────────────────────────┐
            │        ArcanaMacApp          │  executable — launches ArcanaShellApp
            └──────────────┬───────────────┘
                           │
            ┌──────────────▼───────────────┐
            │         ArcanaShell          │  SwiftUI desktop shell (window, tabs,
            │  (SwiftUI + AppKit)          │  sidebar, menus, settings, view factory)
            └───┬───────────┬──────────┬───┘
                │           │          │
      ┌─────────▼──┐  ┌─────▼──────┐  ┌▼───────────┐
      │ArcanaPlugins│ │ArcanaModel │  │ (ArcanaKit)│  iOS-derived base (kept, not on the
      └─────┬───────┘ │(SwiftData, │  └────────────┘  shell path)
            │         │ CryptoKit) │
   ┌────────▼───────┐ └────────────┘
   │ArcanaPlugin-   │
   │  Contracts     │        ArcanaSync  ── zero-dependency CRDT engine (VectorClock, LWW/MV
   └────────────────┘                       registers, ConflictResolver, SyncService)
```

## Modules

| Module | Role | Depends on |
|---|---|---|
| **ArcanaSync** | CRDT sync engine — `VectorClock`, `LWWRegister`/`LWWMap`, `MVRegister`, `ConflictResolver`, `SyncableEntity`, `SyncService`. Port of `Arcana.Sync`. | — (nothing) |
| **ArcanaPluginContracts** | Plugin contracts — `ArcanaPlugin`, `PluginContext`, contribution defs, `MessageBus`/`EventAggregator`, `PluginPermission`, manifest, validators. | — |
| **ArcanaPlugins** | Plugin runtime — registries, message bus, permission manager, `PluginBase`, `PluginManager`, reference `CustomerModulePlugin`. Port of `Arcana.Plugins`. | ArcanaPluginContracts |
| **ArcanaModel** | Domain + identity + auth — SwiftData `@Model`s (Customer/Product/Order, User/Role/Permission/Audit), services, PBKDF2 hashing, HMAC tokens, Keychain, RBAC resolution. | — |
| **ArcanaShell** | macOS desktop shell — `NavigationSplitView` + document tabs, `MenuBarExtra`, `Settings`, dynamic main menu, `ViewFactoryRegistry`, theme/localization. | ArcanaPluginContracts, ArcanaPlugins, ArcanaModel |
| **ArcanaKit** | The iOS-derived Clean Architecture base (Core/Domain/Data/Presentation) carried over in P1. | swift-dependencies, Alamofire, LRUCache |
| **ArcanaMacApp** | Thin executable — `ArcanaShellApp.main()`. | ArcanaKit, ArcanaShell |

## Dependency rules (enforced by arch-qube)

Inner layers never import outer ones:

- **ArcanaSync** and **ArcanaModel** are standalone — they import no other fleet module.
- **ArcanaPluginContracts** imports no implementation module.
- **ArcanaPlugins** may import only its contracts.
- **ArcanaShell** must not reach into **ArcanaKit** (the shell is the macOS-native surface).
- Nothing imports the executable target.

`scripts/arch-qube.sh` greps the module sources for forbidden `import`s and fails the build on
any violation (it must be 100% green). `arch-qube.sh selftest` first proves the gate detects a
known-bad import, guarding against a false-green.

## Concurrency

The whole package compiles in **Swift 6 language mode** (`.swiftLanguageMode(.v6)`) with zero
strict-concurrency diagnostics. Plugin-facing UI surfaces are `@MainActor`; the runtime services
(registries, bus, permission manager) are lock-guarded `Sendable`, so background code can still
publish to them.

## Porting status

See [`docs/PORT_STATUS.md`](docs/PORT_STATUS.md). P0–P6 complete: scaffold, Swift base, Swift 6
uplift, CRDT sync, plugin system, desktop shell, feature modules + RBAC, and CI.
