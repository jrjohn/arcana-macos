//
//  Plugin.swift
//  ArcanaPluginContracts — Swift port of Arcana.Plugins.Contracts (IPlugin / PluginMetadata).
//
//  The VS Code-style plugin contract. On macOS there is no DLL hot-loading (the Windows
//  PluginLoadContext / collectible-assembly model has no ARC equivalent), so plugins are
//  static Swift modules that conform to `ArcanaPlugin` and self-register at launch. The
//  lifecycle, contribution model, messaging, permissions, and health surface are all ported
//  faithfully; dynamic load/unload/install is intentionally out of scope (see PORT_STATUS).
//

import Foundation

/// The plugin category taxonomy — the "18 plugin types" (order preserved from the C# enum).
public enum PluginType: String, Sendable, Codable, CaseIterable {
    case menu, functionTree, view, widget, theme, module, service, dataSource
    case export, `import`, print, auth, sync, analytics, notification
    case entityExtension, viewExtension, workflow
}

/// A plugin's lifecycle state.
public enum PluginState: String, Sendable, Codable {
    case unknown, notLoaded, loaded, activating, active, deactivating, deactivated, uninstalled, error
}

/// Immutable identity + descriptor for a plugin.
public struct PluginMetadata: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String?
    public let author: String?
    public let type: PluginType
    public let iconPath: String?
    public let dependencies: [String]
    public let activationEvents: [String]

    public init(
        id: String,
        name: String,
        version: String,
        description: String? = nil,
        author: String? = nil,
        type: PluginType = .module,
        iconPath: String? = nil,
        dependencies: [String] = [],
        activationEvents: [String] = []
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.author = author
        self.type = type
        self.iconPath = iconPath
        self.dependencies = dependencies
        self.activationEvents = activationEvents
    }
}

/// The base plugin contract. A plugin is activated with a `PluginContext` (host services),
/// registers its contributions, and tears them down on deactivation.
///
/// `@MainActor`-isolated: plugins contribute UI (menus / views / commands) consumed by the
/// SwiftUI desktop shell, so the whole plugin-facing surface runs on the main actor. The
/// registries / bus / stores it talks to are `Sendable` services, so background code can
/// still publish to them.
@MainActor
public protocol ArcanaPlugin: AnyObject {
    var metadata: PluginMetadata { get }
    var state: PluginState { get }
    func activate(context: PluginContext) async throws
    func deactivate() async throws
}

/// A cancellation token for a contribution or subscription (the Swift stand-in for the
/// C# `IDisposable` returned by every `Register*` / `Subscribe`). `Sendable` so tokens from
/// the (background-capable) message bus and the main-actor registries share one type.
public protocol Disposable: AnyObject, Sendable {
    func dispose()
}

/// The host services handed to a plugin at activation. Created and owned by the
/// `PluginManager`; the registries / bus / stores are all `Sendable` services.
@MainActor
public protocol PluginContext: AnyObject {
    var pluginId: String { get }
    var dataPath: String { get }
    var menus: any MenuRegistry { get }
    var views: any ViewRegistry { get }
    var commands: any CommandRegistry { get }
    var messageBus: any MessageBus { get }
    var events: any EventAggregator { get }
    var sharedState: any SharedStateStore { get }
    /// Plugin-lifetime disposables, disposed and cleared on deactivate.
    var subscriptions: [any Disposable] { get set }
}
