//
//  CompositionRoot.swift
//  ArcanaShell — assembles the plugin manager, the SwiftData container, the built-in
//  plugins, and the view-factory registry. The macOS analogue of App.OnLaunched's
//  InitializePluginsAsync + database bootstrap.
//

import SwiftUI
import SwiftData
import ArcanaPlugins
import ArcanaModel

public enum CompositionRoot {

    /// Builds a fully-wired `ShellModel`: SwiftData container (seeded) + plugin manager +
    /// built-in plugins + view factories (incl. the real SwiftData-backed Customer list).
    @MainActor
    public static func makeShell(inMemory: Bool = false) -> ShellModel {
        // SwiftData container. In-memory for tests/previews; on disk for the real app, at a
        // versioned store URL so a schema bump starts a clean store instead of colliding with
        // an older on-disk schema. Falls back to in-memory if the store can't be opened.
        let schema = Schema(ArcanaSchema.models)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            let base = URL.applicationSupportDirectory.appending(path: "Arcana", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            configuration = ModelConfiguration(url: base.appending(path: "arcana-v2.store"))
        }
        let container = (try? ModelContainer(for: schema, configurations: configuration))
            ?? (try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))

        // First-launch identity seed (admin + system roles/permissions) + demo data, idempotent.
        IdentitySeed.seed(context: container.mainContext)
        SampleData.seed(context: container.mainContext)

        let manager = PluginManager()
        manager.register(CoreMenuPlugin())
        manager.register(CustomerModulePlugin())

        let factory = ViewFactoryRegistry()
        factory.register("HomePage") { AnyView(HomeView()) }
        factory.register("CustomerListPage") { AnyView(CustomersView()) }
        factory.register("ProductListPage") { AnyView(ProductsView()) }
        factory.register("OrderListPage") { AnyView(OrdersView()) }
        factory.register("ReportsPage") { AnyView(ReportsView()) }
        factory.register("PluginManagerPage") { AnyView(PluginManagerView(manager: manager)) }
        factory.register("UsersPage") { AnyView(UsersView()) }
        factory.register("SyncPage") { AnyView(SyncView()) }

        return ShellModel(manager: manager, viewFactory: factory,
                          modelContainer: container, currentUser: CurrentUserService())
    }
}
