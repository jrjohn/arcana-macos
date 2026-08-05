//
//  Identity.swift
//  ArcanaModel — identity / RBAC entities, ported from Arcana.Domain.Entities.Identity.
//  Junctions carry expiry + (for direct grants) an isGranted deny flag, both honored by the
//  permission resolver.
//

import Foundation
import SwiftData

@Model
public final class User {
    /// Stable integer identity that the junction tables reference (assigned at seed/create).
    public var entityId: Int
    @Attribute(.unique) public var username: String
    public var email: String?
    public var displayName: String
    public var passwordHash: String
    public var isActive: Bool
    public var isLocked: Bool
    public var lockedUntil: Date?
    public var failedLoginAttempts: Int
    public var lastLoginAt: Date?
    public var passwordChangedAt: Date?
    public var mustChangePassword: Bool
    public var refreshToken: String?
    public var refreshTokenExpiresAt: Date?

    public var createdAt: Date
    public var isSoftDeleted: Bool

    public init(entityId: Int = 0, username: String, displayName: String, passwordHash: String, email: String? = nil, isActive: Bool = true) {
        self.entityId = entityId
        self.username = username
        self.displayName = displayName
        self.passwordHash = passwordHash
        self.email = email
        self.isActive = isActive
        self.isLocked = false
        self.failedLoginAttempts = 0
        self.mustChangePassword = false
        self.createdAt = Date()
        self.isSoftDeleted = false
    }
}

@Model
public final class Role {
    /// Stable integer identity that the junction tables reference.
    public var entityId: Int
    @Attribute(.unique) public var name: String
    public var displayName: String
    public var roleDescription: String?
    public var isSystem: Bool
    public var priority: Int
    public var createdAt: Date
    public var isSoftDeleted: Bool

    public init(entityId: Int = 0, name: String, displayName: String, isSystem: Bool = false, priority: Int = 0) {
        self.entityId = entityId
        self.name = name
        self.displayName = displayName
        self.isSystem = isSystem
        self.priority = priority
        self.createdAt = Date()
        self.isSoftDeleted = false
    }
}

@Model
public final class AppPermission {
    @Attribute(.unique) public var code: String
    public var displayName: String
    public var permissionDescription: String?
    public var category: String
    public var isSystem: Bool

    public init(code: String, displayName: String, category: String, isSystem: Bool = true) {
        self.code = code
        self.displayName = displayName
        self.category = category
        self.isSystem = isSystem
    }
}

@Model
public final class UserRole {
    public var userId: Int
    public var roleId: Int
    public var assignedAt: Date
    public var assignedBy: String?
    public var expiresAt: Date?
    public var isSoftDeleted: Bool

    public init(userId: Int, roleId: Int, expiresAt: Date? = nil) {
        self.userId = userId
        self.roleId = roleId
        self.assignedAt = Date()
        self.expiresAt = expiresAt
        self.isSoftDeleted = false
    }
}

@Model
public final class RolePermission {
    public var roleId: Int
    public var permissionCode: String
    public var grantedAt: Date
    public var isSoftDeleted: Bool

    public init(roleId: Int, permissionCode: String) {
        self.roleId = roleId
        self.permissionCode = permissionCode
        self.grantedAt = Date()
        self.isSoftDeleted = false
    }
}

@Model
public final class UserPermission {
    public var userId: Int
    public var permissionCode: String
    /// false = an explicit DENY that overrides any role grant.
    public var isGranted: Bool
    public var assignedAt: Date
    public var expiresAt: Date?
    public var isSoftDeleted: Bool

    public init(userId: Int, permissionCode: String, isGranted: Bool = true, expiresAt: Date? = nil) {
        self.userId = userId
        self.permissionCode = permissionCode
        self.isGranted = isGranted
        self.assignedAt = Date()
        self.expiresAt = expiresAt
        self.isSoftDeleted = false
    }
}

public enum AuditEventType: String, Sendable, Codable {
    case loginSuccess, loginFailed, logout, passwordChanged, accountLocked, accountUnlocked
    case permissionGranted, permissionRevoked, roleAssigned, roleRevoked, accessDenied
    case userCreated, userUpdated, userDeleted, roleCreated, tokenRefreshed, systemEvent
}

@Model
public final class AuditLog {
    public var eventTypeRaw: String
    public var userId: Int?
    public var username: String?
    public var resource: String?
    public var action: String
    public var details: String?
    public var isSuccess: Bool
    public var errorMessage: String?
    public var timestamp: Date

    public var eventType: AuditEventType {
        get { AuditEventType(rawValue: eventTypeRaw) ?? .systemEvent }
        set { eventTypeRaw = newValue.rawValue }
    }

    public init(eventType: AuditEventType, action: String, isSuccess: Bool = true,
                userId: Int? = nil, username: String? = nil, resource: String? = nil,
                details: String? = nil, errorMessage: String? = nil) {
        self.eventTypeRaw = eventType.rawValue
        self.action = action
        self.isSuccess = isSuccess
        self.userId = userId
        self.username = username
        self.resource = resource
        self.details = details
        self.errorMessage = errorMessage
        self.timestamp = Date()
    }
}

// MARK: - System catalogs

/// The built-in system roles.
public enum SystemRoles {
    public static let administrator = "Administrator"
    public static let manager = "Manager"
    public static let user = "User"
    public static let guest = "Guest"
    public static let all = [administrator, manager, user, guest]
}

/// The built-in permission catalog (the string codes the UI gates off).
public enum SystemPermissions {
    public static let ordersView = "orders.view"
    public static let ordersCreate = "orders.create"
    public static let ordersEdit = "orders.edit"
    public static let ordersDelete = "orders.delete"
    public static let ordersApprove = "orders.approve"
    public static let customersView = "customers.view"
    public static let customersCreate = "customers.create"
    public static let customersEdit = "customers.edit"
    public static let customersDelete = "customers.delete"
    public static let productsView = "products.view"
    public static let productsManageStock = "products.manage_stock"
    public static let usersView = "users.view"
    public static let usersManageRoles = "users.manage_roles"
    public static let rolesManage = "roles.manage"
    public static let pluginsManage = "plugins.manage"
    public static let settingsManage = "settings.manage"
    public static let auditView = "audit.view"

    public static let all = [
        ordersView, ordersCreate, ordersEdit, ordersDelete, ordersApprove,
        customersView, customersCreate, customersEdit, customersDelete,
        productsView, productsManageStock, usersView, usersManageRoles,
        rolesManage, pluginsManage, settingsManage, auditView,
    ]
}
