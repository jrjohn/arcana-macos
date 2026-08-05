//
//  Authorization.swift
//  ArcanaModel — the RBAC permission-resolution algorithm, extracted as a pure function so
//  it can be tested without a database. This is the load-bearing logic shared by login
//  (building AuthenticatedUser) and authorization checks.
//

import Foundation

/// A role granted to a user, with its (optional) expiry and the permission codes it carries.
public struct RoleGrant: Sendable, Equatable {
    public let roleName: String
    public let expiresAt: Date?
    public let permissions: [String]

    public init(roleName: String, expiresAt: Date? = nil, permissions: [String]) {
        self.roleName = roleName
        self.expiresAt = expiresAt
        self.permissions = permissions
    }
}

/// A direct per-user permission grant or deny, with optional expiry.
public struct DirectPermission: Sendable, Equatable {
    public let code: String
    public let isGranted: Bool
    public let expiresAt: Date?

    public init(code: String, isGranted: Bool, expiresAt: Date? = nil) {
        self.code = code
        self.isGranted = isGranted
        self.expiresAt = expiresAt
    }
}

public enum PermissionResolver {
    /// Resolves the effective permission set:
    /// 1. union of all non-expired role permissions, then
    /// 2. apply direct grants (non-expired): granted adds, deny removes (deny wins over role).
    public static func resolve(roles: [RoleGrant], direct: [DirectPermission], now: Date = Date()) -> Set<String> {
        var result = Set<String>()
        for role in roles where !isExpired(role.expiresAt, now) {
            result.formUnion(role.permissions)
        }
        for grant in direct where !isExpired(grant.expiresAt, now) {
            if grant.isGranted { result.insert(grant.code) } else { result.remove(grant.code) }
        }
        return result
    }

    /// The non-expired role names.
    public static func roleNames(_ roles: [RoleGrant], now: Date = Date()) -> [String] {
        roles.filter { !isExpired($0.expiresAt, now) }.map(\.roleName)
    }

    private static func isExpired(_ expiresAt: Date?, _ now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}
