//
//  CoverageTests.swift
//  ArcanaPluginsTests — exercises the contract value types (manifest, health, permissions)
//  and the runtime paths (shared state, event dispose, request timeout, registry queries,
//  manager edge cases) not covered by the behavioral tests.
//

import Testing
import Foundation
@testable import ArcanaPluginContracts
@testable import ArcanaPlugins

@Suite("Manifest & activation events")
struct ManifestCoverageTests {

    @Test("a full manifest with every contribution section decodes")
    func fullManifest() throws {
        let json = """
        {
          "id": "p", "name": "P", "version": "1.0.0", "type": "Module",
          "description": "d", "author": "a", "pluginClass": "PImpl", "icon": "i",
          "dependencies": ["q"], "activationEvents": ["*"],
          "l10n": {"en": "en.json"},
          "contributes": {
            "views": [{"id": "v", "titleKey": "v.t", "type": "Page", "viewClass": "V", "order": 1}],
            "menus": [{"id": "m", "location": "MainMenu", "command": "c", "children": [
                {"id": "m.child", "location": "MainMenu"}]}],
            "commands": [{"id": "c", "title": "C", "category": "cat"}],
            "keybindings": [{"command": "c", "key": "cmd+k", "mac": "cmd+k"}]
          }
        }
        """
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
        #expect(manifest.dependencies == ["q"])
        #expect(manifest.contributes?.menus?.first?.children?.first?.id == "m.child")
        #expect(manifest.contributes?.keybindings?.first?.mac == "cmd+k")
        #expect(manifest.l10n?["en"] == "en.json")
    }

    @Test("activation-event helpers and every prefix parse")
    func activationEvents() {
        #expect(ActivationEvents.forCommand("c") == "onCommand:c")
        #expect(ActivationEvents.forView("v") == "onView:v")
        #expect(ActivationEvents.forLanguage("en") == "onLanguage:en")
        #expect(ActivationEvents.forFileType("txt") == "onFileType:txt")
        #expect(ActivationEvents.parse("onView:v").type == .onView)
        #expect(ActivationEvents.parse("onLanguage:en").type == .onLanguage)
        #expect(ActivationEvents.parse("onUri:x").type == .onUri)
        #expect(ActivationEvents.parse("onConfiguration:c").type == .onConfiguration)
        #expect(ActivationEvents.parse("garbage").type == .unknown)
    }

    @Test("validators emit warnings and successes")
    func validatorEdges() {
        let warn = ContributionValidators.validateView(
            ViewDefinition(id: "v", title: "T"))     // no viewClassName / titleKey ⇒ warnings
        #expect(warn.isValid)
        #expect(!warn.warnings.isEmpty)
        #expect(ContributionValidators.validateCommandId("ok.id").isValid)
        #expect(ContributionValidationResult.withWarnings("w").warnings == ["w"])
    }
}

@Suite("Health & operation result types")
struct HealthCoverageTests {

    @Test("health status, check result, and factories")
    func healthTypes() {
        let detail = HealthCheckResult(checkName: "state", state: .healthy, message: "ok", duration: .milliseconds(2))
        let status = PluginHealthStatus(pluginId: "p", pluginName: "P", state: .degraded,
                                        message: "m", memoryUsageBytes: 100, errorCount: 1, details: [detail])
        #expect(status.state == .degraded)
        #expect(status.details.count == 1)
        #expect(PluginHealthCheckResult.healthy("ok").state == .healthy)
        #expect(PluginHealthCheckResult.degraded("d").state == .degraded)
        #expect(PluginHealthCheckResult.unhealthy("u").state == .unhealthy)
    }

    @Test("operation result and state-change")
    func operationTypes() {
        #expect(PluginOperationResult.succeeded("p", message: "ok").success)
        #expect(!PluginOperationResult.failed("p", message: "no", errorCode: "e").success)
        let change = PluginStateChange(pluginId: "p", oldState: .loaded, newState: .active)
        #expect(change.newState == .active)
    }
}

@Suite("Runtime services — remaining paths")
struct RuntimeServiceCoverageTests {

    @Test("shared state store: set / get / remove / onChange")
    func sharedState() {
        let store = SharedStateStoreImpl()
        let seen = Box<Int?>(nil)
        let token = store.onChange("k", as: Int.self) { seen.value = $0 }
        store.set("k", 5)
        #expect(store.get("k", as: Int.self) == 5)
        #expect(seen.value == 5)
        #expect(store.containsKey("k"))
        #expect(store.remove("k"))
        #expect(!store.containsKey("k"))
        token.dispose()
    }

    @Test("event aggregator stops after dispose")
    func eventDispose() {
        struct E: ApplicationEvent { let timestamp = Date(); let sourcePluginId: String? = nil }
        let events = EventAggregatorImpl()
        let count = Box(0)
        let token = events.subscribe(E.self) { _ in count.value += 1 }
        events.publish(E())
        token.dispose()
        events.publish(E())
        #expect(count.value == 1)
    }

    @Test("message bus: async subscribe, unsubscribe, request timeout")
    func messageBusExtra() async {
        struct M: Sendable { let n: Int }
        struct Q: Sendable {}
        struct A: Sendable {}
        let bus = MessageBusImpl()
        let sum = Box(0)
        let token = bus.subscribe(M.self) { (m: M) async in sum.value += m.n }
        await bus.publish(M(n: 3))
        #expect(sum.value == 3)
        token.dispose()
        await bus.publish(M(n: 10))
        #expect(sum.value == 3)
        // No handler + a timeout ⇒ nil (covers the timeout race path).
        let answer = await bus.request(Q(), responseType: A.self, timeout: .milliseconds(50))
        #expect(answer == nil)
    }

    @Test("registry queries: module default tabs and by-module menu items")
    func registryQueries() {
        let views = ViewRegistryImpl()
        views.registerView(ViewDefinition(id: "t", title: "T", moduleId: "mod", isModuleDefaultTab: true))
        views.registerView(ViewDefinition(id: "other", title: "O"))
        #expect(views.moduleDefaultTabs(moduleId: "mod").map(\.id) == ["t"])
        #expect(views.allViews().count == 2)

        let menus = MenuRegistryImpl()
        menus.registerMenuItem(MenuItemDefinition(id: "a", title: "A", location: .quickAccess, moduleId: "mod"))
        #expect(menus.menuItems(at: .quickAccess, moduleId: "mod").count == 1)
        #expect(menus.allMenuItems().count == 1)

        let commands = CommandRegistryImpl()
        commands.registerCommand("c") { }
        #expect(commands.hasCommand("c"))
        #expect(commands.commands() == ["c"])
    }

    @Test("permission manager: grant / revoke / default")
    func permissions() {
        let manager = PluginPermissionManagerImpl()
        manager.grantPermission("p", .readLocalData)
        #expect(manager.hasPermission("p", .readLocalData))
        manager.revokePermission("p", .readLocalData)
        #expect(!manager.hasPermission("p", .readLocalData))
        manager.registerManifest("p", PluginPermissionManifest(requiredPermissions: .networkAccess))
        #expect(manager.manifest("p")?.requiredPermissions == .networkAccess)
        manager.grantDefaultPermissions("p")
        #expect(manager.permissions("p") == .networkAccess)
    }
}

@Suite("PluginManager edge cases")
@MainActor
struct ManagerEdgeCoverageTests {

    @Test("unknown plugin activate / deactivate return failures")
    func unknown() async {
        let manager = PluginManager()
        #expect(!(await manager.activate(pluginId: "nope")).success)
        #expect(!(await manager.deactivate(pluginId: "nope")).success)
    }

    @Test("circular dependencies are detected on activateAll")
    func circular() async {
        let manager = PluginManager()
        manager.register(CyclePlugin(id: "x", deps: ["y"]))
        manager.register(CyclePlugin(id: "y", deps: ["x"]))
        await #expect(throws: PluginManagerError.self) { try await manager.activateAll() }
    }

    @Test("deactivate tears down a plugin's contributions")
    func teardown() async {
        let manager = PluginManager()
        manager.register(CustomerModulePlugin())
        _ = await manager.activate(pluginId: "arcana.module.customer")
        #expect(!manager.menus.allMenuItems().isEmpty)
        _ = await manager.deactivate(pluginId: "arcana.module.customer")
        #expect(manager.menus.allMenuItems().isEmpty)
    }
}

private final class CyclePlugin: ArcanaPluginBase {
    let id: String
    let deps: [String]
    init(id: String, deps: [String]) { self.id = id; self.deps = deps }
    override var metadata: PluginMetadata {
        PluginMetadata(id: id, name: id, version: "1.0.0", dependencies: deps)
    }
}

/// Thread-safe box for capturing values from `@Sendable` handlers.
private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
