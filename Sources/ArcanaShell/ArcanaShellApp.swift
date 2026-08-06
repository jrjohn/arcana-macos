//
//  ArcanaShellApp.swift
//  ArcanaShell — the macOS app: a document-tab window, a Settings scene, a dynamic main
//  menu built from plugin contributions, and a MenuBarExtra. This is the SwiftUI analogue
//  of the Windows MainWindow + App composition.
//

import SwiftUI
import SwiftData
import AppKit
import ArcanaModel

public struct ArcanaShellApp: App {
    @State private var shell: ShellModel
    @State private var theme = ThemeStore()
    @State private var localization = LocalizationStore()
    @State private var dialogs = DialogService()
    @State private var toasts = ToastCenter()

    public init() {
        let composed = CompositionRoot.makeShell()
        _shell = State(initialValue: composed)
        // Screenshot mode: bypass the login gate with a synthetic admin session.
        if ProcessInfo.processInfo.environment["ARCANA_SHOT"] != nil {
            composed.currentUser.setCurrentUser(AuthenticatedUser(
                id: 1, username: "admin", displayName: "Administrator",
                roles: [SystemRoles.administrator], permissions: Set(SystemPermissions.all)))
        }
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
            .environment(dialogs)
            .environment(toasts)
            .shellUIServices(dialogs, toasts)
            .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1400, height: 900)
        .defaultPosition(.topLeading)
        .modelContainer(shell.modelContainer)
        .commands {
            ShellCommands(shell: shell)
        }

        // Popped-out order documents (tear-off windows).
        WindowGroup("Order", id: "order", for: PersistentIdentifier.self) { $orderID in
            OrderWindowView(orderID: orderID)
        }
        .modelContainer(shell.modelContainer)

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
                    leafButton(node)
                } else {
                    Menu(node.item.title) { menuContent(node.children) }
                }
            }
        )
    }

    @ViewBuilder
    private func leafButton(_ node: MenuNode) -> some View {
        let button = Button(node.item.title) {
            if let command = node.item.command { shell.runCommand(command) }
        }
        if let shortcut = node.item.shortcut, let keys = Self.parseShortcut(shortcut) {
            button.keyboardShortcut(keys)
        } else {
            button
        }
    }

    /// Parses a menu `Shortcut` string ("Ctrl+Shift+O", "Cmd+N") into a SwiftUI shortcut.
    /// Windows `Ctrl` maps to the macOS Command key.
    static func parseShortcut(_ string: String) -> KeyboardShortcut? {
        let parts = string.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyPart = parts.last, let character = keyPart.lowercased().first else { return nil }
        var modifiers: EventModifiers = []
        for part in parts.dropLast() {
            switch part.lowercased() {
            case "cmd", "command", "ctrl", "control", "⌘": modifiers.insert(.command)
            case "shift", "⇧": modifiers.insert(.shift)
            case "alt", "option", "opt", "⌥": modifiers.insert(.option)
            default: break
            }
        }
        if modifiers.isEmpty { modifiers = [.command] }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
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
