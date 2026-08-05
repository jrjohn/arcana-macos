//
//  AppSettings.swift
//  ArcanaShell — persisted shell settings (theme + language), ported from the Windows
//  AppSettingsService. Windows wrote settings.json under %LocalAppData%; macOS uses
//  UserDefaults (thread-safe, so this is `@unchecked Sendable`).
//

import Foundation

public final class AppSettings: @unchecked Sendable {
    public static let shared = AppSettings()

    private let defaults: UserDefaults
    private enum Key {
        static let theme = "arcana.themeId"
        static let language = "arcana.languageCode"
        static let sidebarVisible = "arcana.sidebarVisible"
        static let statusBarVisible = "arcana.statusBarVisible"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var themeId: String {
        get { defaults.string(forKey: Key.theme) ?? "system" }
        set { defaults.set(newValue, forKey: Key.theme) }
    }

    public var languageCode: String {
        get { defaults.string(forKey: Key.language) ?? AppLanguage.default.rawValue }
        set { defaults.set(newValue, forKey: Key.language) }
    }

    public var sidebarVisible: Bool {
        get { defaults.object(forKey: Key.sidebarVisible) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.sidebarVisible) }
    }

    public var statusBarVisible: Bool {
        get { defaults.object(forKey: Key.statusBarVisible) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.statusBarVisible) }
    }
}
