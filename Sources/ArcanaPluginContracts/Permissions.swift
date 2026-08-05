//
//  Permissions.swift
//  ArcanaPluginContracts — the plugin permission model, ported from IPluginPermissions.
//  The C# `[Flags] enum` becomes a Swift `OptionSet` (the idiomatic bitflag type).
//

import Foundation

/// A plugin's capability set. 20 primitive bits plus composite convenience sets, matching
/// the Windows `[Flags] PluginPermission` bit-for-bit.
public struct PluginPermission: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let none: PluginPermission = []

    public static let readLocalData = PluginPermission(rawValue: 1 << 0)
    public static let writeLocalData = PluginPermission(rawValue: 1 << 1)
    public static let readFileSystem = PluginPermission(rawValue: 1 << 2)
    public static let writeFileSystem = PluginPermission(rawValue: 1 << 3)
    public static let networkAccess = PluginPermission(rawValue: 1 << 4)
    public static let webSocketAccess = PluginPermission(rawValue: 1 << 5)
    public static let readDatabase = PluginPermission(rawValue: 1 << 6)
    public static let writeDatabase = PluginPermission(rawValue: 1 << 7)
    public static let createWindows = PluginPermission(rawValue: 1 << 8)
    public static let createDialogs = PluginPermission(rawValue: 1 << 9)
    public static let accessClipboard = PluginPermission(rawValue: 1 << 10)
    public static let showNotifications = PluginPermission(rawValue: 1 << 11)
    public static let interPluginComm = PluginPermission(rawValue: 1 << 12)
    public static let accessSharedState = PluginPermission(rawValue: 1 << 13)
    public static let executeCommands = PluginPermission(rawValue: 1 << 14)
    public static let registerMenus = PluginPermission(rawValue: 1 << 15)
    public static let registerViews = PluginPermission(rawValue: 1 << 16)
    public static let accessCredentials = PluginPermission(rawValue: 1 << 17)
    public static let executeProcess = PluginPermission(rawValue: 1 << 18)
    public static let accessHardware = PluginPermission(rawValue: 1 << 19)

    /// A safe default for UI plugins.
    public static let basicPlugin: PluginPermission = [
        .readLocalData, .writeLocalData, .createDialogs,
        .interPluginComm, .registerMenus, .registerViews,
    ]
    /// Basic plus outbound network.
    public static let networkPlugin: PluginPermission = basicPlugin.union(.networkAccess)
    /// All 20 primitive bits (granted to built-in plugins).
    public static let fullAccess = PluginPermission(rawValue: (1 << 20) - 1)
}

/// A request to use a permission (optionally scoped to a resource).
public struct PermissionRequest: Sendable, Equatable {
    public let pluginId: String
    public let permission: PluginPermission
    public let resource: String?
    public let reason: String?

    public init(pluginId: String, permission: PluginPermission, resource: String? = nil, reason: String? = nil) {
        self.pluginId = pluginId
        self.permission = permission
        self.resource = resource
        self.reason = reason
    }
}

/// The outcome of a permission check.
public struct PermissionCheckResult: Sendable, Equatable {
    public let granted: Bool
    public let deniedPermissions: PluginPermission
    public let message: String?

    public init(granted: Bool, deniedPermissions: PluginPermission = .none, message: String? = nil) {
        self.granted = granted
        self.deniedPermissions = deniedPermissions
        self.message = message
    }

    public static func allow() -> PermissionCheckResult {
        PermissionCheckResult(granted: true)
    }
    public static func deny(_ denied: PluginPermission, message: String? = nil) -> PermissionCheckResult {
        PermissionCheckResult(granted: false, deniedPermissions: denied, message: message)
    }
}

/// A plugin's declared permission requirements.
public struct PluginPermissionManifest: Sendable, Equatable {
    public let requiredPermissions: PluginPermission
    public let optionalPermissions: PluginPermission
    public let permissionReasons: [Int: String]

    public init(
        requiredPermissions: PluginPermission = .none,
        optionalPermissions: PluginPermission = .none,
        permissionReasons: [Int: String] = [:]
    ) {
        self.requiredPermissions = requiredPermissions
        self.optionalPermissions = optionalPermissions
        self.permissionReasons = permissionReasons
    }
}

/// Grants, checks, and persists plugin permissions.
public protocol PluginPermissionManager: Sendable {
    func hasPermission(_ pluginId: String, _ permission: PluginPermission) -> Bool
    func checkPermission(_ request: PermissionRequest) -> PermissionCheckResult
    func grantPermission(_ pluginId: String, _ permission: PluginPermission)
    func revokePermission(_ pluginId: String, _ permission: PluginPermission)
    func permissions(_ pluginId: String) -> PluginPermission
    func setPermissions(_ pluginId: String, _ permissions: PluginPermission)
    func manifest(_ pluginId: String) -> PluginPermissionManifest?
    func registerManifest(_ pluginId: String, _ manifest: PluginPermissionManifest)
}
