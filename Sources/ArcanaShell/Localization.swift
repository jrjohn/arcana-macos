//
//  Localization.swift
//  ArcanaShell — localization store, ported from the Windows LocalizationService.
//
//  SwiftUI re-renders on `@Observable` change, so switching language just republishes the
//  table — no manual UI rebuild (the Windows shell had to rebuild menus/tabs by hand).
//

import SwiftUI

/// The app's supported languages (matching the Windows shell: zh-TW / en-US / ja-JP).
public enum AppLanguage: String, CaseIterable, Sendable, Identifiable {
    case zhTW = "zh-TW"
    case enUS = "en-US"
    case jaJP = "ja-JP"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .zhTW: return "繁體中文"
        case .enUS: return "English"
        case .jaJP: return "日本語"
        }
    }

    public static let `default` = AppLanguage.enUS
}

/// The live localization table. `string(_:)` resolves a key, falling back to the key itself.
@MainActor
@Observable
public final class LocalizationStore {
    public private(set) var language: AppLanguage
    private var table: [String: String]
    private let settings: AppSettings

    public init(settings: AppSettings = .shared) {
        self.settings = settings
        let language = AppLanguage(rawValue: settings.languageCode) ?? .default
        self.language = language
        self.table = Self.table(for: language)
    }

    /// Resolves a localization key (returns the key unchanged if absent).
    public func string(_ key: String) -> String {
        table[key] ?? key
    }

    /// Switches language and persists the choice; the UI re-renders automatically.
    public func setLanguage(_ language: AppLanguage) {
        self.language = language
        self.table = Self.table(for: language)
        settings.languageCode = language.rawValue
    }

    public var available: [AppLanguage] { AppLanguage.allCases }

    // A small built-in table for the shell chrome; plugins ship their own strings.
    private static func table(for language: AppLanguage) -> [String: String] {
        switch language {
        case .enUS:
            return [
                "app.title": "Arcana", "menu.file": "File", "menu.edit": "Edit",
                "menu.view": "View", "menu.business": "Business", "menu.reports": "Reports",
                "menu.help": "Help", "nav.home": "Home", "nav.customers": "Customers",
                "nav.products": "Products", "nav.orders": "Orders", "nav.plugins": "Plugins",
                "status.ready": "Ready",
            ]
        case .zhTW:
            return [
                "app.title": "Arcana", "menu.file": "檔案", "menu.edit": "編輯",
                "menu.view": "檢視", "menu.business": "業務", "menu.reports": "報表",
                "menu.help": "說明", "nav.home": "首頁", "nav.customers": "客戶",
                "nav.products": "產品", "nav.orders": "訂單", "nav.plugins": "外掛",
                "status.ready": "就緒",
            ]
        case .jaJP:
            return [
                "app.title": "Arcana", "menu.file": "ファイル", "menu.edit": "編集",
                "menu.view": "表示", "menu.business": "業務", "menu.reports": "レポート",
                "menu.help": "ヘルプ", "nav.home": "ホーム", "nav.customers": "顧客",
                "nav.products": "製品", "nav.orders": "注文", "nav.plugins": "プラグイン",
                "status.ready": "準備完了",
            ]
        }
    }
}
