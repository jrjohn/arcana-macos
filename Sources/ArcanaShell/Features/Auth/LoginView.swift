//
//  LoginView.swift
//  ArcanaShell — the sign-in screen. Gates the whole app: the shell only appears once
//  `CurrentUserService` is authenticated (via AuthService).
//

import SwiftUI
import ArcanaModel

struct LoginView: View {
    let shell: ShellModel
    @State private var username = "admin"
    @State private var password = "admin"
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield")
                .font(.system(size: 46))
                .foregroundStyle(.tint)
            Text("Sign in to Arcana").font(.title2.bold())

            VStack(spacing: 10) {
                TextField("Username", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .onSubmit(login)
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 260)

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }

            Button("Sign In", action: login)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(username.isEmpty || password.isEmpty)

            Text("Default administrator: admin / admin")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func login() {
        let auth = AuthService(context: shell.modelContainer.mainContext, session: shell.currentUser)
        switch auth.authenticate(username: username, password: password) {
        case .success:
            errorMessage = nil
        case .failure(let error):
            errorMessage = error.message
        }
    }
}

/// Helper for signing out, callable from menus / status bar.
@MainActor
func signOut(_ shell: ShellModel) {
    AuthService(context: shell.modelContainer.mainContext, session: shell.currentUser).logout()
}
