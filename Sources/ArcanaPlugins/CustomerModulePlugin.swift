//
//  CustomerModulePlugin.swift
//  ArcanaPlugins — the canonical reference plugin, ported from the Windows
//  CustomerModulePlugin: a programmatic (non-manifest) module that contributes a view,
//  menu items, and commands.
//
//  Navigation is a host-UI concern (wired up in the desktop-shell phase), so here the
//  commands publish a `NavigationRequested` message on the bus instead of calling a
//  navigation service directly.
//

import Foundation
import ArcanaPluginContracts

/// A request to navigate to a view — published by plugin commands, consumed by the host shell.
public struct NavigationRequested: Sendable, Equatable {
    public enum Mode: Sendable, Equatable { case current, newTab }
    public let viewId: String
    public let mode: Mode
    public init(viewId: String, mode: Mode = .current) {
        self.viewId = viewId
        self.mode = mode
    }
}

/// Reference module plugin: contributes the Customer list view, its menu entries, and the
/// `customer.list` / `customer.new` commands.
public final class CustomerModulePlugin: ArcanaPluginBase {

    public override var metadata: PluginMetadata {
        PluginMetadata(
            id: "arcana.module.customer",
            name: "Customer Module",
            version: "1.0.0",
            description: "Customer management module",
            author: "Arcana",
            type: .module)
    }

    public override func registerContributions(_ context: PluginContext) {
        registerView(ViewDefinition(
            id: "CustomerListPage",
            title: "Customers",
            titleKey: "customer.list",
            icon: "person.2",
            type: .page,
            viewClassName: "CustomerListView",
            category: "Business"))

        registerMenuItems(
            MenuItemDefinition(
                id: "menu.business.customer",
                title: "Customers",
                location: .mainMenu,
                parentId: "menu.business",
                icon: "person.2",
                order: 10),
            MenuItemDefinition(
                id: "menu.business.customer.list",
                title: "Customer List",
                location: .mainMenu,
                parentId: "menu.business.customer",
                command: "customer.list",
                order: 1),
            MenuItemDefinition(
                id: "menu.business.customer.new",
                title: "New Customer",
                location: .mainMenu,
                parentId: "menu.business.customer",
                command: "customer.new",
                order: 2))

        registerMenuItem(MenuItemDefinition(
            id: "quick.newCustomer",
            title: "New Customer",
            location: .quickAccess,
            command: "customer.new",
            group: "business"))

        let bus = context.messageBus
        registerCommand("customer.list") {
            await bus.publish(NavigationRequested(viewId: "CustomerListPage", mode: .current))
        }
        registerCommand("customer.new") {
            await bus.publish(NavigationRequested(viewId: "CustomerDetailPage", mode: .newTab))
        }
    }
}
