//
//  Permissions.swift
//  ArcanaPlugins — in-memory plugin permission manager.
//  (Disk persistence to `plugin_permissions.json` is a host concern, deferred.)
//

import Foundation
import ArcanaPluginContracts

/// In-memory bitflag permission store. Built-in plugins are granted `.fullAccess`; external
/// plugins default to their manifest's required permissions, else `.basicPlugin`.
public final class PluginPermissionManagerImpl: PluginPermissionManager, @unchecked Sendable {
    private let lock = NSLock()
    private var grants: [String: PluginPermission] = [:]
    private var manifests: [String: PluginPermissionManifest] = [:]

    public init() {}

    public func hasPermission(_ pluginId: String, _ permission: PluginPermission) -> Bool {
        permissions(pluginId).contains(permission)
    }

    public func checkPermission(_ request: PermissionRequest) -> PermissionCheckResult {
        let granted = permissions(request.pluginId)
        let denied = request.permission.subtracting(granted)
        if denied.isEmpty { return .allow() }
        return .deny(denied, message: "Plugin '\(request.pluginId)' is missing required permissions")
    }

    public func grantPermission(_ pluginId: String, _ permission: PluginPermission) {
        lock.lock(); grants[pluginId, default: .none].formUnion(permission); lock.unlock()
    }

    public func revokePermission(_ pluginId: String, _ permission: PluginPermission) {
        lock.lock(); grants[pluginId, default: .none].subtract(permission); lock.unlock()
    }

    public func permissions(_ pluginId: String) -> PluginPermission {
        lock.lock(); defer { lock.unlock() }
        return grants[pluginId] ?? .none
    }

    public func setPermissions(_ pluginId: String, _ permissions: PluginPermission) {
        lock.lock(); grants[pluginId] = permissions; lock.unlock()
    }

    public func manifest(_ pluginId: String) -> PluginPermissionManifest? {
        lock.lock(); defer { lock.unlock() }
        return manifests[pluginId]
    }

    public func registerManifest(_ pluginId: String, _ manifest: PluginPermissionManifest) {
        lock.lock(); manifests[pluginId] = manifest; lock.unlock()
    }

    // MARK: - Convenience grants (ported from GrantBuiltIn / GrantDefault)

    /// Grants a built-in plugin full access.
    public func grantBuiltInPermissions(_ pluginId: String) {
        setPermissions(pluginId, .fullAccess)
    }

    /// Grants an external plugin its manifest-required permissions, else `.basicPlugin`.
    public func grantDefaultPermissions(_ pluginId: String) {
        let required = manifest(pluginId)?.requiredPermissions ?? .basicPlugin
        setPermissions(pluginId, required.isEmpty ? .basicPlugin : required)
    }
}
