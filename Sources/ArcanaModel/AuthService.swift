//
//  AuthService.swift
//  ArcanaModel — the login flow that ties the auth primitives together: verify password,
//  resolve the user's effective roles + permissions (via PermissionResolver), set the
//  session, and write an audit record.
//

import Foundation
import SwiftData

@MainActor
public final class AuthService {
    private let context: ModelContext
    private let hasher: PasswordHasher
    private let session: CurrentUserService

    public init(context: ModelContext, session: CurrentUserService, hasher: PasswordHasher = PasswordHasher()) {
        self.context = context
        self.hasher = hasher
        self.session = session
    }

    /// Verifies credentials, resolves the user's permissions, and starts a session.
    @discardableResult
    public func authenticate(username: String, password: String) -> AppResult<AuthenticatedUser> {
        guard let user = fetchUser(username), !user.isSoftDeleted else {
            audit(.loginFailed, username: username, action: "authenticate", success: false, error: "unknown user")
            return .failure(.auth("Invalid username or password"))
        }
        guard user.isActive else {
            audit(.loginFailed, userId: user.entityId, username: username, action: "authenticate", success: false, error: "inactive")
            return .failure(.auth("Account is inactive"))
        }
        guard hasher.verify(password, hash: user.passwordHash) else {
            user.failedLoginAttempts += 1
            audit(.loginFailed, userId: user.entityId, username: username, action: "authenticate", success: false, error: "bad password")
            try? context.save()
            return .failure(.auth("Invalid username or password"))
        }

        user.failedLoginAttempts = 0
        user.lastLoginAt = Date()
        let authenticated = buildAuthenticatedUser(user)
        session.setCurrentUser(authenticated)
        audit(.loginSuccess, userId: user.entityId, username: username, action: "authenticate", success: true)
        try? context.save()
        return .success(authenticated)
    }

    public func logout() {
        if let id = session.userId, let name = session.username {
            audit(.logout, userId: id, username: name, action: "logout", success: true)
            try? context.save()
        }
        session.clearCurrentUser()
    }

    /// Resolves a user's effective roles + permissions (role union, then direct grant/deny).
    public func buildAuthenticatedUser(_ user: User, now: Date = Date()) -> AuthenticatedUser {
        let userId = user.entityId
        let userRoles = (try? context.fetch(FetchDescriptor<UserRole>(
            predicate: #Predicate { $0.userId == userId && !$0.isSoftDeleted }))) ?? []

        var grants: [RoleGrant] = []
        for userRole in userRoles {
            let roleId = userRole.roleId
            guard let role = (try? context.fetch(FetchDescriptor<Role>(
                predicate: #Predicate { $0.entityId == roleId && !$0.isSoftDeleted })))?.first else { continue }
            let perms = ((try? context.fetch(FetchDescriptor<RolePermission>(
                predicate: #Predicate { $0.roleId == roleId && !$0.isSoftDeleted }))) ?? []).map(\.permissionCode)
            grants.append(RoleGrant(roleName: role.name, expiresAt: userRole.expiresAt, permissions: perms))
        }

        let directRows = (try? context.fetch(FetchDescriptor<UserPermission>(
            predicate: #Predicate { $0.userId == userId && !$0.isSoftDeleted }))) ?? []
        let direct = directRows.map { DirectPermission(code: $0.permissionCode, isGranted: $0.isGranted, expiresAt: $0.expiresAt) }

        return AuthenticatedUser(
            id: userId,
            username: user.username,
            displayName: user.displayName,
            email: user.email,
            roles: PermissionResolver.roleNames(grants, now: now),
            permissions: PermissionResolver.resolve(roles: grants, direct: direct, now: now))
    }

    // MARK: - Internals

    private func fetchUser(_ username: String) -> User? {
        try? context.fetch(FetchDescriptor<User>(predicate: #Predicate { $0.username == username })).first
    }

    private func audit(_ event: AuditEventType, userId: Int? = nil, username: String? = nil,
                       action: String, success: Bool, error: String? = nil) {
        context.insert(AuditLog(eventType: event, action: action, isSuccess: success,
                                userId: userId, username: username, errorMessage: error))
    }
}
