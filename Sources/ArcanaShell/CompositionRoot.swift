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
        // SwiftData container. In-memory for tests/previews; on disk for the real app.
        let container = (try? ModelContainer(
            for: Schema(ArcanaSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)))
            ?? (try! ModelContainer(
                for: Schema(ArcanaSchema.models),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))

        // First-launch identity seed (admin + system roles/permissions) + demo data, idempotent.
        IdentitySeed.seed(context: container.mainContext)
        SampleData.seed(context: container.mainContext)

        let manager = PluginManager()
        manager.register(CoreMenuPlugin())
        manager.register(CustomerModulePlugin())

        let factory = ViewFactoryRegistry()
        factory.register("HomePage") { AnyView(HomeView()) }
        factory.register("CustomerListPage") { AnyView(CustomerListView()) }   // real SwiftData view
        factory.register("CustomerDetailPage") { AnyView(SimpleListPlaceholder(title: "Customer", systemImage: "person.crop.circle")) }
        factory.register("ProductListPage") { AnyView(SimpleListPlaceholder(title: "Products", systemImage: "shippingbox")) }
        factory.register("OrderListPage") { AnyView(OrdersView()) }
        factory.register("ReportsPage") { AnyView(SimpleListPlaceholder(title: "Reports", systemImage: "chart.bar")) }
        factory.register("PluginManagerPage") { AnyView(PluginManagerView(manager: manager)) }

        return ShellModel(manager: manager, viewFactory: factory, modelContainer: container)
    }
}
