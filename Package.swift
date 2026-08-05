// swift-tools-version: 6.0
//
//  Arcana macOS — a Local-First, Plugin-Everything macOS desktop app,
//  the Swift 6 / SwiftUI port of arcana-windows (WinUI 3 / .NET 10).
//
//  The Clean Architecture layers (Core / Domain / Data / Presentation) are the
//  faithful Swift base carried over from arcana-ios; the desktop shell, the CRDT
//  sync engine, and the plugin system are the net-new macOS work (see docs/PORT_PLAN.md).
//
import PackageDescription

let package = Package(
    name: "ArcanaMacOS",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "ArcanaKit", targets: ["ArcanaKit"]),
        .library(name: "ArcanaSync", targets: ["ArcanaSync"]),
        .library(name: "ArcanaPluginContracts", targets: ["ArcanaPluginContracts"]),
        .library(name: "ArcanaPlugins", targets: ["ArcanaPlugins"]),
        .library(name: "ArcanaShell", targets: ["ArcanaShell"]),
        .executable(name: "ArcanaMacApp", targets: ["ArcanaMacApp"]),
    ],
    dependencies: [
        // Modern, compile-time-keyed DI (same as the arcana-ios base).
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.1.0"),
        // Networking — carried over from the ported Core layer (macOS-capable).
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.9.0"),
        // In-memory LRU cache — the second layer of the offline-first cache stack.
        .package(url: "https://github.com/nicklockwood/LRUCache", from: "1.0.4"),
    ],
    targets: [
        // The whole app, as a library: layers + the SwiftUI App itself (public entry
        // `ArcanaApp`). Keeping the App here lets every layer stay `internal` while the
        // thin executable below only needs the one public symbol.
        // The CRDT sync engine — a faithful Swift port of the Windows `Arcana.Sync`
        // assembly (VectorClock / LWW / MVRegister / ConflictResolver / SyncService).
        // Pure Swift, zero external dependencies, its own target so the boundary mirrors
        // the .NET assembly split.
        .target(
            name: "ArcanaSync",
            path: "Sources/ArcanaSync",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // The plugin system — a faithful Swift port of the Windows Arcana.Plugins assembly
        // split. Contracts are pure declarations; the runtime (registries, message bus,
        // permissions, plugin base + manager) is the static-registration adaptation
        // (macOS forbids DLL hot-loading). Both zero-dependency, own targets.
        .target(
            name: "ArcanaPluginContracts",
            path: "Sources/ArcanaPluginContracts",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "ArcanaPlugins",
            dependencies: ["ArcanaPluginContracts"],
            path: "Sources/ArcanaPlugins",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // The macOS desktop shell (P4): SwiftUI NavigationSplitView + document tabs +
        // MenuBarExtra + Settings + a dynamic main menu built from plugin contributions.
        .target(
            name: "ArcanaShell",
            dependencies: ["ArcanaPluginContracts", "ArcanaPlugins"],
            path: "Sources/ArcanaShell",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "ArcanaKit",
            dependencies: [
                "ArcanaSync",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "LRUCache", package: "LRUCache"),
            ],
            path: "Sources/ArcanaKit",
            swiftSettings: [
                // Swift 6 strict concurrency (P1.5): ApiService is an actor; domain/data
                // protocols and value types are Sendable; the SwiftData DAO / repository /
                // analytics tracker are @MainActor; DI globals are nonisolated(unsafe).
                .swiftLanguageMode(.v6)
            ]
        ),
        // Thin launcher: `ArcanaApp.main()`.
        .executableTarget(
            name: "ArcanaMacApp",
            dependencies: ["ArcanaKit", "ArcanaShell"],
            path: "Sources/ArcanaMacApp",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "ArcanaKitTests",
            dependencies: ["ArcanaKit"],
            path: "Tests/ArcanaKitTests"
        ),
        .testTarget(
            name: "ArcanaSyncTests",
            dependencies: ["ArcanaSync"],
            path: "Tests/ArcanaSyncTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "ArcanaPluginsTests",
            dependencies: ["ArcanaPlugins", "ArcanaPluginContracts"],
            path: "Tests/ArcanaPluginsTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "ArcanaShellTests",
            dependencies: ["ArcanaShell", "ArcanaPlugins", "ArcanaPluginContracts"],
            path: "Tests/ArcanaShellTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
