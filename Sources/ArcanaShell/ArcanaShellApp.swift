//
//  ArcanaShellApp.swift
//  ArcanaShell — the macOS app: a document-tab window, a Settings scene, a dynamic main
//  menu built from plugin contributions, and a MenuBarExtra. This is the SwiftUI analogue
//  of the Windows MainWindow + App composition.
//

import SwiftUI
import SwiftData
import AppKit

public struct ArcanaShellApp: App {
    @State private var shell: ShellModel
    @State private var theme = ThemeStore()
    @State private var localization = LocalizationStore()

    public init() {
        _shell = State(initialValue: CompositionRoot.makeShell())
    }

    public var body: some Scene {
        WindowGroup {
            Group {
                if shell.currentUser.isAuthenticated {
                    ShellView(shell: shell, theme: theme)
                        .task { await shell.bootstrap() }
                } else {
                    LoginView(shell: shell)
                }
            }
            .environment(shell.currentUser)
            .frame(minWidth: 900, minHeight: 560)
        }
        .modelContainer(shell.modelContainer)
        .commands {
            ShellCommands(shell: shell)
        }

        Settings {
            ShellSettingsView(theme: theme, localization: localization)
        }

        MenuBarExtra("Arcana", systemImage: "sparkles") {
            Text("Arcana")
            Divider()
            Button("Quit Arcana") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

/// The dynamic main menu built from plugin-contributed menu items.
struct ShellCommands: Commands {
    var shell: ShellModel

    var body: some Commands {
        CommandMenu("Modules") {
            menuContent(shell.mainMenu)
        }
        CommandMenu("Account") {
            if let user = shell.currentUser.currentUser {
                Text("Signed in as \(user.displayName)")
                Text("Roles: \(user.roles.joined(separator: ", "))")
                Divider()
                Button("Sign Out") { signOut(shell) }
                    .keyboardShortcut("q", modifiers: [.command, .shift])
            }
        }
    }

    // Type-erased so the recursive submenu builder can reference itself.
    private func menuContent(_ nodes: [MenuNode]) -> AnyView {
        AnyView(
            ForEach(nodes) { node in
                if node.isLeaf {
                    Button(node.item.title) {
                        if let command = node.item.command { shell.runCommand(command) }
                    }
                } else {
                    Menu(node.item.title) { menuContent(node.children) }
                }
            }
        )
    }
}

/// Theme + language preferences.
struct ShellSettingsView: View {
    @Bindable var theme: ThemeStore
    @Bindable var localization: LocalizationStore

    var body: some View {
        Form {
            Picker("Theme", selection: themeBinding) {
                ForEach(theme.available) { Text($0.name).tag($0.id) }
            }
            Picker("Language", selection: languageBinding) {
                ForEach(localization.available) { Text($0.displayName).tag($0) }
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var themeBinding: Binding<String> {
        Binding(get: { theme.current.id }, set: { theme.apply(id: $0) })
    }
    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { localization.language }, set: { localization.setLanguage($0) })
    }
}
