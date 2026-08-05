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
        .target(
            name: "ArcanaKit",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "LRUCache", package: "LRUCache"),
            ],
            path: "Sources/ArcanaKit",
            swiftSettings: [
                // P1 ships in Swift 5 language mode so the ported arcana-ios base runs
                // on macOS now; the Swift 6 strict-concurrency uplift (Sendable domain
                // protocols, isolated DI, actor DAOs) is the next phase (P1.5).
                .swiftLanguageMode(.v5)
            ]
        ),
        // Thin launcher: `ArcanaApp.main()`.
        .executableTarget(
            name: "ArcanaMacApp",
            dependencies: ["ArcanaKit"],
            path: "Sources/ArcanaMacApp",
            swiftSettings: [
                // P1 ships in Swift 5 language mode so the ported arcana-ios base runs
                // on macOS now; the Swift 6 strict-concurrency uplift (Sendable domain
                // protocols, isolated DI, actor DAOs) is the next phase (P1.5).
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "ArcanaKitTests",
            dependencies: ["ArcanaKit"],
            path: "Tests/ArcanaKitTests"
        ),
    ]
)
