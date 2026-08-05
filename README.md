# arcana-macos

A Local-First, Plugin-Everything **macOS** desktop application — the Swift 6 / SwiftUI
port of [`arcana-windows`](https://github.com/jrjohn/arcana-windows) (WinUI 3 / .NET 10).

The Clean Architecture layers (Core / Domain / Data / Presentation) are carried over from
the Swift [`arcana-ios`](https://github.com/jrjohn/arcana-ios) base; the desktop shell, the
CRDT sync engine, and the plugin system are the net-new macOS work.

## Build & run

```bash
swift build          # compile
swift test           # run tests (Swift Testing)
swift run ArcanaMacApp   # launch (dev)
```

Requires Xcode 26+ / Swift 6.x, macOS 15+.

## Architecture

```
Sources/
  ArcanaKit/            one library: the layers + the SwiftUI App (public `ArcanaApp`)
    ArcanaCore/         DI (swift-dependencies), Network, Config, Localization, Analytics
    ArcanaDomain/       Model, Service, Validation (pure Swift)
    ArcanaData/         SwiftData Local DAO, Remote DAO, OfflineFirst Repository, PendingChange queue
    ArcanaPresentation/ MVVM (Input/Output/Effect), NavGraph, Screens, Components, Theme
    App/                ArcanaApp (WindowGroup + Settings), Compat (macOS shims)
  ArcanaMacApp/         thin launcher — `ArcanaApp.main()`
Tests/                  Swift Testing, mirrored by layer
```

MVVM is **Input / Output / Effect**: `@Observable @MainActor` view models with a nested
`enum Input`, `enum Effect`, `private(set)` output state, and `send(_:)`.

## Status

See [`docs/PORT_STATUS.md`](docs/PORT_STATUS.md). **P0 (scaffold) + P1 (Swift base) are
done and the package builds + tests green.** Next: the Swift 6 strict-concurrency uplift
(P1.5), then the CRDT sync engine (P2), the plugin system (P3), the desktop shell (P4),
feature modules + RBAC (P5), and CI (P6).

## License

MIT (matching the Arcana fleet).
