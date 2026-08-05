//
//  Theme.swift
//  ArcanaShell — theming store, ported from the Windows ThemeService.
//
//  WinUI overwrote resource-dictionary brushes at runtime; SwiftUI drives color through the
//  environment instead, so a theme here is a base color scheme + an accent, exposed by an
//  `@Observable` store the shell reads via `.tint` / `.preferredColorScheme`.
//

import SwiftUI

/// A named theme: a base light/dark preference plus an accent color.
public struct ThemeDefinition: Identifiable, Sendable, Equatable {
    public enum Base: String, Sendable { case system, light, dark }

    public let id: String
    public let name: String
    public let base: Base
    public let accent: Color

    public init(id: String, name: String, base: Base, accent: Color) {
        self.id = id
        self.name = name
        self.base = base
        self.accent = accent
    }

    /// The SwiftUI color scheme this theme forces (nil = follow the system).
    public var colorScheme: ColorScheme? {
        switch base {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public extension ThemeDefinition {
    /// The built-in themes (System / Light / Dark + a few accent variants).
    static let all: [ThemeDefinition] = [
        ThemeDefinition(id: "system", name: "System", base: .system, accent: .accentColor),
        ThemeDefinition(id: "light", name: "Light", base: .light, accent: .blue),
        ThemeDefinition(id: "dark", name: "Dark", base: .dark, accent: .blue),
        ThemeDefinition(id: "oceanBlue", name: "Ocean Blue", base: .dark, accent: .teal),
        ThemeDefinition(id: "purpleNight", name: "Purple Night", base: .dark, accent: .purple),
        ThemeDefinition(id: "forest", name: "Forest", base: .light, accent: .green),
    ]

    static let `default` = all[0]

    static func with(id: String) -> ThemeDefinition {
        all.first { $0.id == id } ?? .default
    }
}

/// The shell's live theme selection.
@MainActor
@Observable
public final class ThemeStore {
    public private(set) var current: ThemeDefinition
    private let settings: AppSettings

    public init(settings: AppSettings = .shared) {
        self.settings = settings
        self.current = ThemeDefinition.with(id: settings.themeId)
    }

    public var colorScheme: ColorScheme? { current.colorScheme }
    public var accent: Color { current.accent }

    public var available: [ThemeDefinition] { ThemeDefinition.all }

    /// Selects a theme by id and persists the choice.
    public func apply(id: String) {
        current = ThemeDefinition.with(id: id)
        settings.themeId = id
    }
}
