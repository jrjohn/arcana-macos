//
//  CompositionRoot.swift
//  ArcanaShell — assembles the plugin manager, registers the built-in plugins, and wires
//  the view-factory registry. This is the macOS analogue of App.OnLaunched's
//  InitializePluginsAsync composition step.
//

import SwiftUI
import ArcanaPlugins

public enum CompositionRoot {

    /// Builds a fully-wired `ShellModel`: manager + built-in plugins + view factories.
    @MainActor
    public static func makeShell() -> ShellModel {
        let manager = PluginManager()

        // Built-in plugins (order mirrors the Windows composition root: core chrome first).
        manager.register(CoreMenuPlugin())
        manager.register(CustomerModulePlugin())

        // Compiled-in view factories (P5 swaps the placeholders for real feature views).
        let factory = ViewFactoryRegistry()
        factory.register("HomePage") { AnyView(HomeView()) }
        factory.register("CustomerListPage") { AnyView(SimpleListPlaceholder(title: "Customers", systemImage: "person.2")) }
        factory.register("CustomerDetailPage") { AnyView(SimpleListPlaceholder(title: "Customer", systemImage: "person.crop.circle")) }
        factory.register("ProductListPage") { AnyView(SimpleListPlaceholder(title: "Products", systemImage: "shippingbox")) }
        factory.register("OrderListPage") { AnyView(SimpleListPlaceholder(title: "Orders", systemImage: "cart")) }
        factory.register("ReportsPage") { AnyView(SimpleListPlaceholder(title: "Reports", systemImage: "chart.bar")) }
        factory.register("PluginManagerPage") { AnyView(PluginManagerView(manager: manager)) }

        return ShellModel(manager: manager, viewFactory: factory)
    }
}
