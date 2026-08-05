//
//  ShellModel.swift
//  ArcanaShell — the shell's observable state + navigation, ported from the Windows
//  MainWindow's tab/menu/nav coordination. This is the testable core; the SwiftUI views
//  are thin renderers over it.
//

import SwiftUI
import ArcanaPluginContracts
import ArcanaPlugins

/// One open document tab.
public struct OpenTab: Identifiable, Sendable, Equatable {
    public let id: String
    public let viewId: String
    public let title: String
    public let icon: String

    public init(id: String, viewId: String, title: String, icon: String) {
        self.id = id
        self.viewId = viewId
        self.title = title
        self.icon = icon
    }
}

/// A sidebar entry (a built-in nav destination or a plugin FunctionTree item).
public struct SidebarItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let isCommand: Bool

    public init(id: String, title: String, systemImage: String, isCommand: Bool = false) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isCommand = isCommand
    }
}

@MainActor
@Observable
public final class ShellModel {

    public let manager: PluginManager
    public let viewFactory: ViewFactoryRegistry

    public private(set) var tabs: [OpenTab] = []
    public var selectedTabId: String?
    public var sidebarSelection: String?

    public private(set) var mainMenu: [MenuNode] = []
    public private(set) var quickActions: [MenuItemDefinition] = []
    public private(set) var functionTreeItems: [MenuItemDefinition] = []

    public var statusMessage: String = "Ready"

    private var backStack: [String] = []
    private var forwardStack: [String] = []
    private var subscriptions: [any Disposable] = []

    /// The fixed built-in sidebar destinations (before any FunctionTree contributions).
    public static let builtInSidebar: [SidebarItem] = [
        SidebarItem(id: "HomePage", title: "Home", systemImage: "house"),
        SidebarItem(id: "CustomerListPage", title: "Customers", systemImage: "person.2"),
        SidebarItem(id: "ProductListPage", title: "Products", systemImage: "shippingbox"),
        SidebarItem(id: "OrderListPage", title: "Orders", systemImage: "cart"),
        SidebarItem(id: "ReportsPage", title: "Reports", systemImage: "chart.bar"),
        SidebarItem(id: "PluginManagerPage", title: "Plugins", systemImage: "puzzlepiece"),
    ]

    public init(manager: PluginManager, viewFactory: ViewFactoryRegistry) {
        self.manager = manager
        self.viewFactory = viewFactory
    }

    // MARK: - Bootstrap

    /// Activates all startup plugins, wires navigation, refreshes contributions, opens Home.
    public func bootstrap() async {
        // Plugin commands request navigation by publishing on the bus; the shell listens.
        // The async handler lets `publish` await it, so a command's navigation is applied
        // by the time `execute` returns (deterministic — also nice for tests).
        let token = manager.messageBus.subscribe(NavigationRequested.self) { [weak self] request in
            await MainActor.run { self?.handle(request) }
        }
        subscriptions.append(token)

        try? await manager.activateAll()
        refresh()
        openTab(viewId: "HomePage", title: "Home", icon: "house")
    }

    /// Re-reads the contribution registries into the observable menu state.
    public func refresh() {
        mainMenu = MenuTree.build(from: manager.menus.allMenuItems())
        quickActions = manager.menus.menuItems(at: .quickAccess)
        functionTreeItems = manager.menus.menuItems(at: .functionTree)
    }

    // MARK: - Sidebar

    public var sidebarItems: [SidebarItem] {
        let dynamic = functionTreeItems.map {
            SidebarItem(id: $0.command ?? $0.id, title: $0.title,
                        systemImage: $0.icon ?? "doc", isCommand: $0.command != nil)
        }
        return Self.builtInSidebar + dynamic
    }

    public func selectSidebar(_ item: SidebarItem) {
        if item.isCommand {
            runCommand(item.id)
        } else {
            openTab(viewId: item.id, title: item.title, icon: item.systemImage)
        }
    }

    // MARK: - Tabs

    /// Opens (or, for single-instance views, re-selects) a tab.
    @discardableResult
    public func openTab(viewId: String, title: String, icon: String, multiInstance: Bool = false) -> String {
        if !multiInstance, let existing = tabs.first(where: { $0.viewId == viewId }) {
            selectedTabId = existing.id
            return existing.id
        }
        let id = multiInstance ? "\(viewId)#\(tabs.count)-\(UUID().uuidString.prefix(8))" : viewId
        tabs.append(OpenTab(id: id, viewId: viewId, title: title, icon: icon))
        if let current = selectedTabId { backStack.append(current) }
        forwardStack.removeAll()
        selectedTabId = id
        return id
    }

    public func closeTab(id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if selectedTabId == id {
            selectedTabId = tabs.last?.id
        }
    }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }

    public func goBack() {
        guard let previous = backStack.popLast() else { return }
        if let current = selectedTabId { forwardStack.append(current) }
        selectedTabId = previous
    }

    public func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let current = selectedTabId { backStack.append(current) }
        selectedTabId = next
    }

    // MARK: - Commands & navigation

    public func runCommand(_ commandId: String) {
        Task { await manager.commands.execute(commandId) }
    }

    private func handle(_ request: NavigationRequested) {
        let definition = manager.views.view(id: request.viewId)
        let title = definition?.title ?? request.viewId
        let icon = definition?.icon ?? "doc"
        let multiInstance = request.mode == .newTab || (definition?.canHaveMultipleInstances ?? false)
        openTab(viewId: request.viewId, title: title, icon: icon, multiInstance: multiInstance)
    }

    // MARK: - Content

    /// The SwiftUI content for a tab's view id (a placeholder if nothing is registered).
    public func content(forViewId viewId: String) -> AnyView {
        viewFactory.make(viewId) ?? AnyView(MissingViewPlaceholder(viewId: viewId))
    }
}
