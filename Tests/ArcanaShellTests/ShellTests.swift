//
//  ShellTests.swift
//  ArcanaShellTests — the shell's testable core: menu-tree building, tab management,
//  plugin-driven navigation, the view-factory, and the theme/localization stores.
//

import Testing
import SwiftUI
@testable import ArcanaPluginContracts
@testable import ArcanaPlugins
@testable import ArcanaShell

@Suite("MenuTree")
struct MenuTreeTests {

    @Test("builds a nested tree from mainMenu roots + parentId, ordered")
    func nestedTree() {
        let items = [
            MenuItemDefinition(id: "menu.business", title: "Business", location: .mainMenu, order: 10),
            MenuItemDefinition(id: "menu.file", title: "File", location: .mainMenu, order: 0),
            MenuItemDefinition(id: "menu.business.customer", title: "Customers",
                               location: .mainMenu, parentId: "menu.business", order: 1),
            MenuItemDefinition(id: "menu.business.customer.new", title: "New",
                               location: .mainMenu, parentId: "menu.business.customer", command: "customer.new", order: 2),
        ]
        let tree = MenuTree.build(from: items)
        #expect(tree.map(\.id) == ["menu.file", "menu.business"])          // ordered by order
        let business = tree.first { $0.id == "menu.business" }
        #expect(business?.children.first?.id == "menu.business.customer")
        #expect(business?.children.first?.children.first?.item.command == "customer.new")
    }

    @Test("orphan children (no mainMenu root) produce no roots")
    func orphansDropped() {
        let items = [
            MenuItemDefinition(id: "x", title: "X", location: .mainMenu, parentId: "missing", order: 0),
        ]
        #expect(MenuTree.build(from: items).isEmpty)
    }
}

@Suite("ViewFactoryRegistry")
@MainActor
struct ViewFactoryTests {
    @Test("registers and resolves a view; reports missing")
    func registerResolve() {
        let registry = ViewFactoryRegistry()
        registry.register("HomePage") { AnyView(Text("home")) }
        #expect(registry.hasView("HomePage"))
        #expect(registry.make("HomePage") != nil)
        #expect(registry.make("Nope") == nil)
    }
}

@Suite("ShellModel tabs & navigation")
@MainActor
struct ShellModelTests {

    @Test("single-instance tabs de-dupe; multi-instance open new")
    func tabDeduping() {
        let shell = CompositionRoot.makeShell(inMemory: true)
        let first = shell.openTab(viewId: "CustomerListPage", title: "Customers", icon: "person.2")
        let again = shell.openTab(viewId: "CustomerListPage", title: "Customers", icon: "person.2")
        #expect(first == again)                                   // re-selected, not duplicated
        #expect(shell.tabs.filter { $0.viewId == "CustomerListPage" }.count == 1)

        let a = shell.openTab(viewId: "OrderDetailPage", title: "Order", icon: "cart", multiInstance: true)
        let b = shell.openTab(viewId: "OrderDetailPage", title: "Order", icon: "cart", multiInstance: true)
        #expect(a != b)                                           // two distinct instances
        #expect(shell.tabs.filter { $0.viewId == "OrderDetailPage" }.count == 2)
    }

    @Test("closing the selected tab selects another")
    func closeSelected() {
        let shell = CompositionRoot.makeShell(inMemory: true)
        shell.openTab(viewId: "A", title: "A", icon: "a")
        let b = shell.openTab(viewId: "B", title: "B", icon: "b")
        #expect(shell.selectedTabId == b)
        shell.closeTab(id: b)
        #expect(shell.selectedTabId == "A")
        #expect(!shell.tabs.contains { $0.id == b })
    }

    @Test("bootstrap activates plugins, builds the menu tree, opens Home")
    func bootstrap() async {
        let shell = CompositionRoot.makeShell(inMemory: true)
        await shell.bootstrap()

        // Core + Customer plugins are active.
        #expect(shell.manager.plugin(id: "arcana.core.menu")?.state == .active)
        #expect(shell.manager.plugin(id: "arcana.module.customer")?.state == .active)

        // The menu tree has the Business root with the Customer submenu nested under it.
        let business = shell.mainMenu.first { $0.id == "menu.business" }
        #expect(business != nil)
        #expect(business?.children.contains { $0.id == "menu.business.customer" } == true)

        // Home tab is open.
        #expect(shell.tabs.contains { $0.viewId == "HomePage" })
    }

    @Test("a plugin command's navigation opens the target tab")
    func commandNavigation() async {
        let shell = CompositionRoot.makeShell(inMemory: true)
        await shell.bootstrap()

        // customer.list publishes NavigationRequested; the async bus handler runs before
        // execute returns, so the tab is present synchronously afterward.
        _ = await shell.manager.commands.execute("customer.list")
        #expect(shell.tabs.contains { $0.viewId == "CustomerListPage" })
    }
}

@Suite("Theme & localization stores")
@MainActor
struct StoreTests {

    private func scratchSettings() -> AppSettings {
        let defaults = UserDefaults(suiteName: "arcana.tests.\(UUID().uuidString)")!
        return AppSettings(defaults: defaults)
    }

    @Test("theme apply updates and persists")
    func themePersists() {
        let settings = scratchSettings()
        let theme = ThemeStore(settings: settings)
        theme.apply(id: "dark")
        #expect(theme.current.id == "dark")
        #expect(theme.colorScheme == .dark)
        #expect(settings.themeId == "dark")
    }

    @Test("language switch updates the table and persists")
    func languagePersists() {
        let settings = scratchSettings()
        let store = LocalizationStore(settings: settings)
        #expect(store.string("nav.home") == "Home")            // default en
        store.setLanguage(.zhTW)
        #expect(store.string("nav.home") == "首頁")
        #expect(settings.languageCode == "zh-TW")
    }
}
