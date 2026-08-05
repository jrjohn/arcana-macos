//
//  ArcanaApp.swift
//  ArcanaKit — the Arcana macOS application entry point.
//
//  Defined inside the library so every Clean Architecture layer stays `internal`;
//  the executable target is a one-line launcher (`ArcanaApp.main()`).
//
//  For P1 this mirrors the arcana-ios `ContentView` (NavigationStack + NavGraph) so
//  the ported screens run unchanged on macOS. The macOS-native desktop shell —
//  NavigationSplitView sidebar, multi-window, MenuBarExtra, `.commands` — arrives in
//  the desktop-shell phase.
//

import SwiftUI
import SwiftData

/// The Arcana macOS app. Launch with `ArcanaApp.main()`.
public struct ArcanaApp: App {
    private let sharedModelContainer: ModelContainer

    public init() {
        // Local-First: SwiftData is the single source of truth. The container and the
        // dependency graph are stood up before any view is created (same order as iOS).
        sharedModelContainer = AppDependencies.createModelContainer()
        MainActor.assumeIsolated {
            AppDependencies.setup(modelContainer: sharedModelContainer)
        }
    }

    public var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(sharedModelContainer)
                .frame(minWidth: 920, minHeight: 620)
        }

        // macOS Preferences (⌘,) — net-new vs iOS; fleshed out in a later phase.
        Settings {
            PreferencesView()
        }
    }
}

// MARK: - Root shell

/// The window's root. P1 keeps the iOS NavigationStack + NavGraph flow verbatim so the
/// ported User CRUD screens work immediately; the desktop-shell phase replaces this with
/// a `NavigationSplitView` and plugin-contributed sidebar sections.
struct RootView: View {
    @State private var navGraph = NavGraph()

    var body: some View {
        NavigationStack(path: $navGraph.path) {
            MainView(viewModel: MainViewModel(navGraph: navGraph))
                .navigationDestination(for: AppRoute.self) { route in
                    NavGraphView.view(for: route, navGraph: navGraph)
                }
        }
        .withNavigation(navGraph)
    }
}

// MARK: - Preferences (placeholder)

struct PreferencesView: View {
    var body: some View {
        Form {
            Section {
                Text("Arcana")
                    .font(.title2.weight(.semibold))
                Text("Local-First · Plugin-Everything · macOS")
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Architecture", value: "Clean + MVVM (Input/Output/Effect)")
                LabeledContent("Persistence", value: "SwiftData (offline-first)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 260)
    }
}
