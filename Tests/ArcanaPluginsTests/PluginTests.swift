//
//  PluginTests.swift
//  ArcanaPluginsTests — the plugin contract + runtime behaviors that matter:
//  permissions algebra, manifest decoding, contribution validation, the in-memory
//  services, and the manager's lifecycle / dependency ordering / activation gating.
//

import Testing
import Foundation
@testable import ArcanaPluginContracts
@testable import ArcanaPlugins

/// Thread-safe box for capturing values from `@Sendable` handlers in tests.
private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

@Suite("Permissions algebra")
struct PermissionTests {

    @Test("composite sets contain their parts")
    func composites() {
        #expect(PluginPermission.basicPlugin.contains(.registerMenus))
        #expect(PluginPermission.basicPlugin.contains(.registerViews))
        #expect(!PluginPermission.basicPlugin.contains(.networkAccess))
        #expect(PluginPermission.networkPlugin.contains(.networkAccess))
        #expect(PluginPermission.networkPlugin.contains(.readLocalData))
        #expect(PluginPermission.fullAccess.contains(.accessHardware))
        #expect(PluginPermission.fullAccess.rawValue == (1 << 20) - 1)
    }

    @Test("checkPermission denies exactly the missing bits")
    func denyMissing() {
        let manager = PluginPermissionManagerImpl()
        manager.setPermissions("p", .basicPlugin)
        let request = PermissionRequest(pluginId: "p", permission: [.registerMenus, .networkAccess])
        let result = manager.checkPermission(request)
        #expect(result.granted == false)
        #expect(result.deniedPermissions == .networkAccess)   // menus granted, network not
    }

    @Test("built-in grant is full access; default grant is basic")
    func grantDefaults() {
        let manager = PluginPermissionManagerImpl()
        manager.grantBuiltInPermissions("builtin")
        #expect(manager.permissions("builtin") == .fullAccess)
        manager.grantDefaultPermissions("external")
        #expect(manager.permissions("external") == .basicPlugin)
    }
}

@Suite("Manifest & validation")
struct ManifestTests {

    @Test("a manifest with contributions decodes")
    func decodeManifest() throws {
        let json = """
        {
          "id": "acme.tool", "name": "Acme", "version": "2.1.0", "type": "Module",
          "activationEvents": ["onCommand:acme.run"],
          "contributes": {
            "commands": [{ "id": "acme.run", "title": "Run" }],
            "views": [{ "id": "acmeView", "titleKey": "acme.view", "type": "Page" }]
          }
        }
        """
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
        #expect(manifest.id == "acme.tool")
        #expect(manifest.version == "2.1.0")
        #expect(manifest.contributes?.commands?.first?.id == "acme.run")
        #expect(manifest.contributes?.views?.first?.titleKey == "acme.view")
    }

    @Test("activation event parsing splits type and argument")
    func parseActivationEvents() {
        #expect(ActivationEvents.parse("onStartup").type == .onStartup)
        #expect(ActivationEvents.parse("*").type == .star)
        let command = ActivationEvents.parse("onCommand:foo.bar")
        #expect(command.type == .onCommand)
        #expect(command.argument == "foo.bar")
    }

    @Test("menu validator accepts valid ids and rejects bad ones")
    func menuValidation() {
        let ok = ContributionValidators.validateMenuItem(
            MenuItemDefinition(id: "menu.file.open", title: "Open", location: .fileMenu, command: "file.open"))
        #expect(ok.isValid)

        let badId = ContributionValidators.validateMenuItem(
            MenuItemDefinition(id: "9bad", title: "X", location: .fileMenu))
        #expect(!badId.isValid)

        let missingTitle = ContributionValidators.validateMenuItem(
            MenuItemDefinition(id: "menu.x", title: "", location: .fileMenu))
        #expect(!missingTitle.isValid)
    }

    @Test("view validator forbids hyphens in ids (stricter than menu ids)")
    func viewValidation() {
        #expect(ContributionValidators.validateView(
            ViewDefinition(id: "customerList", title: "Customers", viewClassName: "V")).isValid)
        // Hyphen is allowed in menu/command ids but NOT in view ids.
        #expect(!ContributionValidators.validateView(
            ViewDefinition(id: "customer-list", title: "Customers")).isValid)
    }

    @Test("command id validator")
    func commandValidation() {
        #expect(ContributionValidators.validateCommandId("customer.new").isValid)
        #expect(!ContributionValidators.validateCommandId("").isValid)
        #expect(!ContributionValidators.validateCommandId("1nope").isValid)
    }
}

@Suite("Registries & messaging")
struct ServiceTests {

    @Test("menu registry filters by location, sorts by order, and disposes")
    func menuRegistry() {
        let registry = MenuRegistryImpl()
        let a = registry.registerMenuItem(MenuItemDefinition(id: "b", title: "B", location: .mainMenu, order: 2))
        registry.registerMenuItem(MenuItemDefinition(id: "a", title: "A", location: .mainMenu, order: 1))
        registry.registerMenuItem(MenuItemDefinition(id: "f", title: "F", location: .fileMenu, order: 1))

        let main = registry.menuItems(at: .mainMenu)
        #expect(main.map(\.id) == ["a", "b"])            // sorted by order
        #expect(registry.menuItems(at: .fileMenu).count == 1)

        a.dispose()
        #expect(registry.menuItems(at: .mainMenu).map(\.id) == ["a"])
    }

    @Test("message bus delivers to subscribers and stops after dispose")
    func messageBusPubSub() async {
        struct Ping: Sendable, Equatable { let n: Int }
        let bus = MessageBusImpl()
        let received = Box(0)
        let token = bus.subscribe(Ping.self) { ping in received.value += ping.n }

        await bus.publish(Ping(n: 5))
        #expect(received.value == 5)

        token.dispose()
        await bus.publish(Ping(n: 100))
        #expect(received.value == 5)                     // no delivery after dispose
    }

    @Test("message bus request/response returns the handler's result")
    func messageBusRequest() async {
        struct Q: Sendable { let x: Int }
        struct A: Sendable, Equatable { let y: Int }
        let bus = MessageBusImpl()
        bus.registerHandler(Q.self, responseType: A.self) { q in A(y: q.x * 2) }

        let answer = await bus.request(Q(x: 21), responseType: A.self, timeout: nil)
        #expect(answer == A(y: 42))

        // No handler registered for this pair ⇒ nil.
        struct Other: Sendable {}
        let none = await bus.request(Other(), responseType: A.self, timeout: nil)
        #expect(none == nil)
    }

    @Test("event aggregator delivers events by type")
    func eventAggregator() {
        struct ThemeChanged: ApplicationEvent { let timestamp = Date(); let sourcePluginId: String? = nil; let name: String }
        let events = EventAggregatorImpl()
        let seen = Box<String?>(nil)
        events.subscribe(ThemeChanged.self) { seen.value = $0.name }
        events.publish(ThemeChanged(name: "dark"))
        #expect(seen.value == "dark")
    }
}

// MARK: - Manager lifecycle (main-actor)

private final class DependentPlugin: ArcanaPluginBase {
    let id: String
    let deps: [String]
    let events: [String]
    init(id: String, deps: [String] = [], events: [String] = []) {
        self.id = id; self.deps = deps; self.events = events
    }
    override var metadata: PluginMetadata {
        PluginMetadata(id: id, name: id, version: "1.0.0", type: .module,
                       dependencies: deps, activationEvents: events)
    }
}

@Suite("PluginManager lifecycle")
@MainActor
struct PluginManagerTests {

    @Test("reference plugin activates and contributes menus + a working command")
    func customerModuleActivates() async {
        let manager = PluginManager()
        manager.register(CustomerModulePlugin())
        try? await manager.activateAll()

        let plugin = manager.plugin(id: "arcana.module.customer")
        #expect(plugin?.state == .active)

        // Its menu items are now registered.
        let mainMenu = manager.menus.menuItems(at: .mainMenu)
        #expect(mainMenu.contains { $0.id == "menu.business.customer" })
        #expect(manager.menus.menuItems(at: .quickAccess).contains { $0.id == "quick.newCustomer" })

        // Executing customer.list publishes a NavigationRequested message.
        let nav = Box<NavigationRequested?>(nil)
        let token = manager.messageBus.subscribe(NavigationRequested.self) { nav.value = $0 }
        _ = await manager.commands.execute("customer.list")
        #expect(nav.value == NavigationRequested(viewId: "CustomerListPage", mode: .current))
        token.dispose()

        // Deactivation tears the contributions down.
        _ = await manager.deactivate(pluginId: "arcana.module.customer")
        #expect(manager.menus.menuItems(at: .mainMenu).isEmpty)
    }

    @Test("dependencies activate before dependents")
    func dependencyOrder() async {
        let manager = PluginManager()
        manager.register(DependentPlugin(id: "base"))
        manager.register(DependentPlugin(id: "feature", deps: ["base"]))

        let result = await manager.activate(pluginId: "feature")
        #expect(result.success)
        #expect(manager.plugin(id: "base")?.state == .active)      // dep pulled up
        #expect(manager.plugin(id: "feature")?.state == .active)
    }

    @Test("a plugin gated on an activation event stays dormant until it fires")
    func activationEventGating() async {
        let manager = PluginManager()
        manager.register(DependentPlugin(id: "lazy", events: ["onCommand:lazy.run"]))
        try? await manager.activateAll()
        #expect(manager.plugin(id: "lazy")?.state != .active)      // not a startup plugin

        await manager.fireActivationEvent(.onCommand, argument: "lazy.run")
        #expect(manager.plugin(id: "lazy")?.state == .active)
    }
}
