//
//  PluginRuntime.swift
//  ArcanaPlugins — the plugin base class, the default context, and the manager.
//
//  This is the static-registration adaptation of the Windows PluginManager: plugins are
//  pre-instantiated Swift modules (no AssemblyLoadContext / reflection). The manager still
//  reproduces the meaningful runtime behavior — dependency-ordered activation, activation-
//  event gating, subscription teardown on deactivate, and a state-change stream. Dynamic
//  load/unload, ZIP install/upgrade/rollback, and the EF version store are host concerns
//  with no macOS equivalent and are out of scope (see PORT_STATUS).
//

import Foundation
import ArcanaPluginContracts

/// Base class real plugins subclass. Handles the activate/deactivate lifecycle, stores the
/// context, and offers the `register*` / `subscribe` / `publish` helpers (each tracked in
/// `context.subscriptions` and torn down on deactivate).
@MainActor
open class ArcanaPluginBase: ArcanaPlugin {

    open var metadata: PluginMetadata {
        fatalError("Subclasses of ArcanaPluginBase must override `metadata`")
    }

    public private(set) var state: PluginState = .notLoaded
    public private(set) var context: PluginContext?

    public init() {}

    public func activate(context: PluginContext) async throws {
        state = .activating
        self.context = context
        do {
            try await onActivate(context)
            registerContributions(context)
            state = .active
        } catch {
            state = .error
            throw error
        }
    }

    public func deactivate() async throws {
        state = .deactivating
        do {
            try await onDeactivate()
            if var ctx = context {
                ctx.subscriptions.forEach { $0.dispose() }
                ctx.subscriptions.removeAll()
                context = ctx
            }
            state = .deactivated
        } catch {
            state = .error
            throw error
        }
    }

    // MARK: - Overridable hooks

    open func onActivate(_ context: PluginContext) async throws {}
    open func onDeactivate() async throws {}
    open func registerContributions(_ context: PluginContext) {}

    // MARK: - Contribution helpers (each tracked for automatic teardown)

    public func registerCommand(_ commandId: String, _ handler: @escaping @Sendable () async -> Void) {
        guard let context else { return }
        context.subscriptions.append(context.commands.registerCommand(commandId, handler))
    }

    public func registerMenuItem(_ item: MenuItemDefinition) {
        guard let context else { return }
        context.subscriptions.append(context.menus.registerMenuItem(item))
    }

    public func registerMenuItems(_ items: MenuItemDefinition...) {
        guard let context else { return }
        context.subscriptions.append(context.menus.registerMenuItems(items))
    }

    public func registerView(_ view: ViewDefinition) {
        guard let context else { return }
        context.subscriptions.append(context.views.registerView(view))
    }

    public func subscribe<Message: Sendable>(
        _ type: Message.Type, _ handler: @escaping @Sendable (Message) -> Void
    ) {
        guard let context else { return }
        context.subscriptions.append(context.messageBus.subscribe(type, handler))
    }

    public func publish<Message: Sendable>(_ message: Message) async {
        await context?.messageBus.publish(message)
    }
}

/// The default `PluginContext` the manager hands to each plugin.
@MainActor
public final class DefaultPluginContext: PluginContext {
    public let pluginId: String
    public let dataPath: String
    public let menus: any MenuRegistry
    public let views: any ViewRegistry
    public let commands: any CommandRegistry
    public let messageBus: any MessageBus
    public let events: any EventAggregator
    public let sharedState: any SharedStateStore
    public var subscriptions: [any Disposable] = []

    public init(
        pluginId: String,
        dataPath: String,
        menus: any MenuRegistry,
        views: any ViewRegistry,
        commands: any CommandRegistry,
        messageBus: any MessageBus,
        events: any EventAggregator,
        sharedState: any SharedStateStore
    ) {
        self.pluginId = pluginId
        self.dataPath = dataPath
        self.menus = menus
        self.views = views
        self.commands = commands
        self.messageBus = messageBus
        self.events = events
        self.sharedState = sharedState
    }
}

/// Errors surfaced by the plugin manager.
public enum PluginManagerError: Error, Sendable, Equatable {
    case unknownPlugin(String)
    case circularDependency([String])
    case missingDependency(plugin: String, dependency: String)
}

/// The static-registration plugin manager: registers pre-instantiated plugins, activates
/// them in dependency order (gated by activation events), and streams state changes.
@MainActor
public final class PluginManager {

    // Shared host services (also handed to every plugin via its context).
    public let menus: any MenuRegistry
    public let views: any ViewRegistry
    public let commands: any CommandRegistry
    public let messageBus: any MessageBus
    public let events: any EventAggregator
    public let sharedState: any SharedStateStore
    public let permissions: PluginPermissionManagerImpl

    private let dataPathRoot: String
    private var plugins: [String: any ArcanaPlugin] = [:]
    private var registrationOrder: [String] = []

    /// A stream of plugin state transitions.
    public let stateChanges: AsyncStream<PluginStateChange>
    private let stateContinuation: AsyncStream<PluginStateChange>.Continuation

    public init(
        dataPathRoot: String = NSTemporaryDirectory() + "arcana/plugins",
        menus: any MenuRegistry = MenuRegistryImpl(),
        views: any ViewRegistry = ViewRegistryImpl(),
        commands: any CommandRegistry = CommandRegistryImpl(),
        messageBus: any MessageBus = MessageBusImpl(),
        events: any EventAggregator = EventAggregatorImpl(),
        sharedState: any SharedStateStore = SharedStateStoreImpl(),
        permissions: PluginPermissionManagerImpl = PluginPermissionManagerImpl()
    ) {
        self.dataPathRoot = dataPathRoot
        self.menus = menus
        self.views = views
        self.commands = commands
        self.messageBus = messageBus
        self.events = events
        self.sharedState = sharedState
        self.permissions = permissions
        let (stream, continuation) = AsyncStream<PluginStateChange>.makeStream()
        self.stateChanges = stream
        self.stateContinuation = continuation
    }

    // MARK: - Registration

    /// Registers a pre-instantiated plugin. Built-ins get `.fullAccess`; others get their
    /// default (manifest-required or `.basicPlugin`) permission set.
    public func register(_ plugin: any ArcanaPlugin, isBuiltIn: Bool = true) {
        let id = plugin.metadata.id
        if plugins[id] == nil { registrationOrder.append(id) }
        plugins[id] = plugin
        if isBuiltIn {
            permissions.grantBuiltInPermissions(id)
        } else {
            permissions.grantDefaultPermissions(id)
        }
    }

    public func plugin(id: String) -> (any ArcanaPlugin)? { plugins[id] }

    public func allPlugins() -> [any ArcanaPlugin] {
        registrationOrder.compactMap { plugins[$0] }
    }

    // MARK: - Activation

    /// Activates a plugin, activating its (registered) dependencies first.
    @discardableResult
    public func activate(pluginId: String) async -> PluginOperationResult {
        guard let plugin = plugins[pluginId] else {
            return .failed(pluginId, message: "Unknown plugin", errorCode: "unknown_plugin")
        }
        if plugin.state == .active { return .succeeded(pluginId, message: "Already active") }

        // Dependencies first.
        for dependency in plugin.metadata.dependencies {
            guard plugins[dependency] != nil else {
                return .failed(pluginId, message: "Missing dependency '\(dependency)'", errorCode: "missing_dependency")
            }
            let result = await activate(pluginId: dependency)
            if !result.success { return result }
        }

        let previous = plugin.state
        emit(pluginId, from: previous, to: .activating)
        let context = makeContext(for: pluginId)
        do {
            try await plugin.activate(context: context)
            emit(pluginId, from: .activating, to: .active)
            return .succeeded(pluginId)
        } catch {
            emit(pluginId, from: .activating, to: .error, message: "\(error)")
            return .failed(pluginId, message: "\(error)", errorCode: "activation_failed")
        }
    }

    /// Deactivates a plugin (its contributions are torn down via its subscriptions).
    @discardableResult
    public func deactivate(pluginId: String) async -> PluginOperationResult {
        guard let plugin = plugins[pluginId] else {
            return .failed(pluginId, message: "Unknown plugin", errorCode: "unknown_plugin")
        }
        guard plugin.state == .active else { return .succeeded(pluginId, message: "Not active") }
        emit(pluginId, from: .active, to: .deactivating)
        do {
            try await plugin.deactivate()
            emit(pluginId, from: .deactivating, to: .deactivated)
            return .succeeded(pluginId)
        } catch {
            emit(pluginId, from: .deactivating, to: .error, message: "\(error)")
            return .failed(pluginId, message: "\(error)", errorCode: "deactivation_failed")
        }
    }

    /// Activates all startup plugins in dependency order (the rest wait for their events).
    public func activateAll() async throws {
        let ids = try topologicalSort(Array(registrationOrder))
        for id in ids where shouldActivateOnStartup(id) {
            await activate(pluginId: id)
        }
    }

    /// Fires an activation event, activating every inactive plugin that subscribes to it.
    public func fireActivationEvent(_ type: ActivationEventType, argument: String? = nil) async {
        for id in registrationOrder {
            guard let plugin = plugins[id], plugin.state != .active else { continue }
            if matches(plugin, type: type, argument: argument) {
                await activate(pluginId: id)
            }
        }
    }

    // MARK: - Internals

    private func makeContext(for pluginId: String) -> DefaultPluginContext {
        DefaultPluginContext(
            pluginId: pluginId,
            dataPath: dataPathRoot + "/" + pluginId,
            menus: menus, views: views, commands: commands,
            messageBus: messageBus, events: events, sharedState: sharedState)
    }

    private func shouldActivateOnStartup(_ pluginId: String) -> Bool {
        guard let plugin = plugins[pluginId] else { return false }
        let eventStrings = plugin.metadata.activationEvents
        if eventStrings.isEmpty { return true }
        return eventStrings.contains(ActivationEvents.onStartup) || eventStrings.contains(ActivationEvents.star)
    }

    private func matches(_ plugin: any ArcanaPlugin, type: ActivationEventType, argument: String?) -> Bool {
        for raw in plugin.metadata.activationEvents {
            if raw == ActivationEvents.star { return true }
            let parsed = ActivationEvents.parse(raw)
            if parsed.type == type {
                if let argument, let parsedArg = parsed.argument {
                    if parsedArg == argument { return true }
                } else {
                    return true
                }
            }
        }
        return false
    }

    /// Orders ids so each plugin's registered dependencies come first; throws on a cycle.
    private func topologicalSort(_ ids: [String]) throws -> [String] {
        var sorted: [String] = []
        var visited: Set<String> = []
        var inProgress: Set<String> = []

        func visit(_ id: String, stack: [String]) throws {
            if visited.contains(id) { return }
            if inProgress.contains(id) { throw PluginManagerError.circularDependency(stack + [id]) }
            inProgress.insert(id)
            if let plugin = plugins[id] {
                for dependency in plugin.metadata.dependencies where plugins[dependency] != nil {
                    try visit(dependency, stack: stack + [id])
                }
            }
            inProgress.remove(id)
            visited.insert(id)
            sorted.append(id)
        }

        for id in ids { try visit(id, stack: []) }
        return sorted
    }

    private func emit(_ pluginId: String, from old: PluginState, to new: PluginState, message: String? = nil) {
        stateContinuation.yield(PluginStateChange(pluginId: pluginId, oldState: old, newState: new, message: message))
    }
}
