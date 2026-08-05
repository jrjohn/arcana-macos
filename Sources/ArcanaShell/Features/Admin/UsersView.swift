//
//  UsersView.swift
//  ArcanaShell — the Identity / RBAC admin: a user list, per-user role assignment, and the
//  resulting effective permissions (resolved through AuthService / PermissionResolver).
//

import SwiftUI
import SwiftData
import ArcanaModel

struct UsersView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<User> { !$0.isSoftDeleted }, sort: \User.username)
    private var users: [User]
    @State private var selectedID: PersistentIdentifier?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Button { newUser() } label: { Label("New User", systemImage: "person.badge.plus") }
                    Spacer()
                }
                .padding(8)
                Divider()
                List(users, selection: $selectedID) { user in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName).font(.headline)
                        Text("@\(user.username)").font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(user.persistentModelID)
                }
            }
            .frame(minWidth: 260, idealWidth: 300)

            Group {
                if let id = selectedID, let user = users.first(where: { $0.persistentModelID == id }) {
                    UserAdminDetail(user: user)
                } else {
                    ContentUnavailableView("Select a user", systemImage: "person.badge.key",
                                           description: Text("Choose a user to manage roles and permissions."))
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity)
        }
    }

    private func newUser() {
        let nextId = (users.map(\.entityId).max() ?? 0) + 1
        let user = User(entityId: nextId, username: "user\(nextId)", displayName: "New User",
                        passwordHash: PasswordHasher().hash("password"), isActive: true)
        context.insert(user)
        try? context.save()
        selectedID = user.persistentModelID
    }
}

struct UserAdminDetail: View {
    @Environment(\.modelContext) private var context
    @Bindable var user: User
    @Query(filter: #Predicate<Role> { !$0.isSoftDeleted }, sort: \Role.name)
    private var roles: [Role]
    @State private var effectivePermissions: [String] = []

    var body: some View {
        Form {
            Section("User") {
                TextField("Display name", text: $user.displayName)
                    .onChange(of: user.displayName) { try? context.save() }
                LabeledContent("Username", value: user.username)
                Toggle("Active", isOn: $user.isActive).onChange(of: user.isActive) { try? context.save() }
                Button("Reset password to “password”") {
                    user.passwordHash = PasswordHasher().hash("password")
                    user.mustChangePassword = true
                    try? context.save()
                }
            }

            Section("Roles") {
                ForEach(roles) { role in
                    Toggle(isOn: roleBinding(role)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(role.displayName)
                            if role.isSystem { Text("system").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
            }

            Section("Effective permissions (\(effectivePermissions.count))") {
                if effectivePermissions.isEmpty {
                    Text("No permissions").foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(effectivePermissions, id: \.self) { code in
                        Label(code, systemImage: "checkmark.seal").font(.callout)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(user.displayName)
        .onAppear { recomputePermissions() }
    }

    private func roleBinding(_ role: Role) -> Binding<Bool> {
        Binding(
            get: { assignment(for: role) != nil },
            set: { assign in
                if assign, assignment(for: role) == nil {
                    context.insert(UserRole(userId: user.entityId, roleId: role.entityId))
                } else if !assign, let existing = assignment(for: role) {
                    context.delete(existing)
                }
                try? context.save()
                recomputePermissions()
            })
    }

    private func assignment(for role: Role) -> UserRole? {
        let userId = user.entityId
        let roleId = role.entityId
        return (try? context.fetch(FetchDescriptor<UserRole>(
            predicate: #Predicate { $0.userId == userId && $0.roleId == roleId && !$0.isSoftDeleted })))?.first
    }

    private func recomputePermissions() {
        let auth = AuthService(context: context, session: CurrentUserService())
        effectivePermissions = auth.buildAuthenticatedUser(user).permissions.sorted()
    }
}
