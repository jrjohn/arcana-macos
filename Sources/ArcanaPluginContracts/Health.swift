//
//  Health.swift
//  ArcanaPluginContracts — plugin health surface, ported from IPluginHealthCheck.
//

import Foundation

/// A plugin's health level.
public enum HealthState: String, Sendable, Codable {
    case healthy, degraded, unhealthy, unknown
}

/// One named health check's result.
public struct HealthCheckResult: Sendable, Equatable, Codable {
    public let checkName: String
    public let state: HealthState
    public let message: String?
    public let duration: Duration

    public init(checkName: String, state: HealthState, message: String? = nil, duration: Duration = .zero) {
        self.checkName = checkName
        self.state = state
        self.message = message
        self.duration = duration
    }
}

/// An aggregate health snapshot for a plugin.
public struct PluginHealthStatus: Sendable, Equatable {
    public let pluginId: String
    public let pluginName: String
    public let state: HealthState
    public let message: String?
    public let checkedAt: Date
    public let responseTime: Duration?
    public let memoryUsageBytes: Int64
    public let errorCount: Int
    public let lastErrorAt: Date?
    public let lastError: String?
    public let details: [HealthCheckResult]

    public init(
        pluginId: String,
        pluginName: String,
        state: HealthState,
        message: String? = nil,
        checkedAt: Date = Date(),
        responseTime: Duration? = nil,
        memoryUsageBytes: Int64 = 0,
        errorCount: Int = 0,
        lastErrorAt: Date? = nil,
        lastError: String? = nil,
        details: [HealthCheckResult] = []
    ) {
        self.pluginId = pluginId
        self.pluginName = pluginName
        self.state = state
        self.message = message
        self.checkedAt = checkedAt
        self.responseTime = responseTime
        self.memoryUsageBytes = memoryUsageBytes
        self.errorCount = errorCount
        self.lastErrorAt = lastErrorAt
        self.lastError = lastError
        self.details = details
    }
}

/// The result a plugin returns from its own health check.
public struct PluginHealthCheckResult: Sendable, Equatable {
    public let state: HealthState
    public let message: String?
    public let checks: [HealthCheckResult]

    public init(state: HealthState, message: String? = nil, checks: [HealthCheckResult] = []) {
        self.state = state
        self.message = message
        self.checks = checks
    }

    public static func healthy(_ message: String? = nil) -> PluginHealthCheckResult {
        PluginHealthCheckResult(state: .healthy, message: message)
    }
    public static func degraded(_ message: String) -> PluginHealthCheckResult {
        PluginHealthCheckResult(state: .degraded, message: message)
    }
    public static func unhealthy(_ message: String) -> PluginHealthCheckResult {
        PluginHealthCheckResult(state: .unhealthy, message: message)
    }
}

/// A plugin that reports its own health.
public protocol PluginHealthCheck: AnyObject {
    func checkHealth() async -> PluginHealthCheckResult
}

/// The outcome of a plugin lifecycle operation (activate / deactivate / etc.).
public struct PluginOperationResult: Sendable, Equatable {
    public let success: Bool
    public let pluginId: String?
    public let message: String?
    public let errorCode: String?

    public init(success: Bool, pluginId: String? = nil, message: String? = nil, errorCode: String? = nil) {
        self.success = success
        self.pluginId = pluginId
        self.message = message
        self.errorCode = errorCode
    }

    public static func succeeded(_ pluginId: String, message: String? = nil) -> PluginOperationResult {
        PluginOperationResult(success: true, pluginId: pluginId, message: message)
    }
    public static func failed(_ pluginId: String?, message: String, errorCode: String? = nil) -> PluginOperationResult {
        PluginOperationResult(success: false, pluginId: pluginId, message: message, errorCode: errorCode)
    }
}

/// A state transition, emitted by the plugin manager.
public struct PluginStateChange: Sendable, Equatable {
    public let pluginId: String
    public let oldState: PluginState
    public let newState: PluginState
    public let message: String?

    public init(pluginId: String, oldState: PluginState, newState: PluginState, message: String? = nil) {
        self.pluginId = pluginId
        self.oldState = oldState
        self.newState = newState
        self.message = message
    }
}
