//
//  Manifest.swift
//  ArcanaPluginContracts — the declarative plugin manifest (`plugin.manifest.json`),
//  activation events, and contribution validators. Ported from
//  Arcana.Plugins.Contracts.Manifest + Validation.
//

import Foundation

// MARK: - Manifest

/// A plugin's declarative manifest. Field names map to the C# JSON wire form.
public struct PluginManifest: Sendable, Codable, Equatable {
    public var id: String
    public var name: String
    public var version: String
    public var description: String?
    public var author: String?
    /// Type name of the `ArcanaPlugin` implementation (the Swift analogue of `pluginClass`).
    public var pluginClass: String?
    public var type: String
    public var dependencies: [String]?
    public var activationEvents: [String]?
    public var contributes: ManifestContributions?
    /// Culture → localization file path.
    public var l10n: [String: String]?
    public var icon: String?

    public init(
        id: String,
        name: String,
        version: String,
        description: String? = nil,
        author: String? = nil,
        pluginClass: String? = nil,
        type: String = "Module",
        dependencies: [String]? = nil,
        activationEvents: [String]? = nil,
        contributes: ManifestContributions? = nil,
        l10n: [String: String]? = nil,
        icon: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.author = author
        self.pluginClass = pluginClass
        self.type = type
        self.dependencies = dependencies
        self.activationEvents = activationEvents
        self.contributes = contributes
        self.l10n = l10n
        self.icon = icon
    }
}

/// The contribution-point sections of a manifest.
public struct ManifestContributions: Sendable, Codable, Equatable {
    public var views: [ManifestViewDefinition]?
    public var menus: [ManifestMenuDefinition]?
    public var commands: [ManifestCommandDefinition]?
    public var keybindings: [ManifestKeybindingDefinition]?

    public init(
        views: [ManifestViewDefinition]? = nil,
        menus: [ManifestMenuDefinition]? = nil,
        commands: [ManifestCommandDefinition]? = nil,
        keybindings: [ManifestKeybindingDefinition]? = nil
    ) {
        self.views = views
        self.menus = menus
        self.commands = commands
        self.keybindings = keybindings
    }
}

public struct ManifestViewDefinition: Sendable, Codable, Equatable {
    public var id: String
    public var titleKey: String
    public var title: String?
    public var icon: String?
    public var type: String
    public var viewClass: String?
    public var category: String?
    public var order: Int?

    public init(id: String, titleKey: String, title: String? = nil, icon: String? = nil,
                type: String = "Page", viewClass: String? = nil, category: String? = nil, order: Int? = nil) {
        self.id = id; self.titleKey = titleKey; self.title = title; self.icon = icon
        self.type = type; self.viewClass = viewClass; self.category = category; self.order = order
    }
}

public struct ManifestMenuDefinition: Sendable, Codable, Equatable {
    public var id: String
    public var titleKey: String?
    public var title: String?
    public var location: String
    public var parentId: String?
    public var icon: String?
    public var shortcut: String?
    public var command: String?
    public var order: Int?
    public var group: String?
    public var when: String?
    public var isSeparator: Bool?
    public var children: [ManifestMenuDefinition]?

    public init(id: String, titleKey: String? = nil, title: String? = nil, location: String,
                parentId: String? = nil, icon: String? = nil, shortcut: String? = nil, command: String? = nil,
                order: Int? = nil, group: String? = nil, when: String? = nil, isSeparator: Bool? = nil,
                children: [ManifestMenuDefinition]? = nil) {
        self.id = id; self.titleKey = titleKey; self.title = title; self.location = location
        self.parentId = parentId; self.icon = icon; self.shortcut = shortcut; self.command = command
        self.order = order; self.group = group; self.when = when; self.isSeparator = isSeparator
        self.children = children
    }
}

public struct ManifestCommandDefinition: Sendable, Codable, Equatable {
    public var id: String
    public var titleKey: String?
    public var title: String?
    public var category: String?
    public var icon: String?

    public init(id: String, titleKey: String? = nil, title: String? = nil, category: String? = nil, icon: String? = nil) {
        self.id = id; self.titleKey = titleKey; self.title = title; self.category = category; self.icon = icon
    }
}

public struct ManifestKeybindingDefinition: Sendable, Codable, Equatable {
    public var command: String
    public var key: String
    public var when: String?
    public var mac: String?
    public var win: String?
    public var linux: String?

    public init(command: String, key: String, when: String? = nil, mac: String? = nil, win: String? = nil, linux: String? = nil) {
        self.command = command; self.key = key; self.when = when; self.mac = mac; self.win = win; self.linux = linux
    }
}

// MARK: - Activation events

/// The parsed kind of an activation event.
public enum ActivationEventType: String, Sendable {
    case unknown, onStartup, onCommand, onView, onLanguage, onFileType
    case onUri, onWorkspaceContains, onConfiguration, onAuthentication, onMenu, star
}

/// Activation-event string constants and parsing (VS Code-style `onCommand:foo`).
public enum ActivationEvents {
    public static let onStartup = "onStartup"
    public static let onCommandPrefix = "onCommand:"
    public static let onViewPrefix = "onView:"
    public static let onLanguagePrefix = "onLanguage:"
    public static let onFileTypePrefix = "onFileType:"
    public static let onUriPrefix = "onUri:"
    public static let onWorkspaceContainsPrefix = "onWorkspaceContains:"
    public static let onConfigurationPrefix = "onConfiguration:"
    public static let onAuthenticationPrefix = "onAuthentication:"
    public static let onMenuPrefix = "onMenu:"
    public static let star = "*"

    public static func forCommand(_ commandId: String) -> String { onCommandPrefix + commandId }
    public static func forView(_ viewId: String) -> String { onViewPrefix + viewId }
    public static func forLanguage(_ languageCode: String) -> String { onLanguagePrefix + languageCode }
    public static func forFileType(_ ext: String) -> String { onFileTypePrefix + ext }

    /// Parses an activation-event string into its type and (optional) argument.
    public static func parse(_ activationEvent: String) -> (type: ActivationEventType, argument: String?) {
        if activationEvent == onStartup { return (.onStartup, nil) }
        if activationEvent == star { return (.star, nil) }
        let prefixes: [(String, ActivationEventType)] = [
            (onCommandPrefix, .onCommand), (onViewPrefix, .onView), (onLanguagePrefix, .onLanguage),
            (onFileTypePrefix, .onFileType), (onUriPrefix, .onUri), (onWorkspaceContainsPrefix, .onWorkspaceContains),
            (onConfigurationPrefix, .onConfiguration), (onAuthenticationPrefix, .onAuthentication), (onMenuPrefix, .onMenu),
        ]
        for (prefix, type) in prefixes where activationEvent.hasPrefix(prefix) {
            return (type, String(activationEvent.dropFirst(prefix.count)))
        }
        return (.unknown, nil)
    }
}

// MARK: - Validation

/// The result of validating a contribution — errors block, warnings advise.
public struct ContributionValidationResult: Sendable, Equatable {
    public let isValid: Bool
    public let errors: [String]
    public let warnings: [String]

    public init(isValid: Bool, errors: [String] = [], warnings: [String] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }

    public static func success() -> ContributionValidationResult {
        ContributionValidationResult(isValid: true)
    }
    public static func failure(_ errors: String...) -> ContributionValidationResult {
        ContributionValidationResult(isValid: false, errors: errors)
    }
    public static func withWarnings(_ warnings: String...) -> ContributionValidationResult {
        ContributionValidationResult(isValid: true, warnings: warnings)
    }
}

/// Contribution id/shape validators, with the same regex rules as the C# validators.
public enum ContributionValidators {
    /// Menu & command ids: letter-first; letters, digits, dot, underscore, hyphen.
    static let menuCommandIdPattern = "^[a-zA-Z][a-zA-Z0-9._-]*$"
    /// View ids: letter-first; letters, digits, underscore only.
    static let viewIdPattern = "^[a-zA-Z][a-zA-Z0-9_]*$"

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    /// Validates a contributed menu item.
    public static func validateMenuItem(_ item: MenuItemDefinition) -> ContributionValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        if item.id.isEmpty { errors.append("Menu item id is required") }
        else if !matches(item.id, menuCommandIdPattern) { errors.append("Menu item id '\(item.id)' has an invalid format") }
        if !item.isSeparator && item.title.isEmpty { errors.append("Menu item '\(item.id)' requires a title unless it is a separator") }
        if let command = item.command, !command.isEmpty, !matches(command, menuCommandIdPattern) {
            warnings.append("Menu item '\(item.id)' command '\(command)' has a non-standard format")
        }
        if item.order < 0 { warnings.append("Menu item '\(item.id)' has a negative order") }
        if item.location == .moduleQuickAccess && (item.moduleId?.isEmpty ?? true) {
            warnings.append("Menu item '\(item.id)' in ModuleQuickAccess should set a moduleId")
        }
        return ContributionValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }

    /// Validates a contributed view.
    public static func validateView(_ view: ViewDefinition) -> ContributionValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        if view.id.isEmpty { errors.append("View id is required") }
        else if !matches(view.id, viewIdPattern) { errors.append("View id '\(view.id)' has an invalid format") }
        if view.title.isEmpty { errors.append("View '\(view.id)' requires a title") }
        if view.viewClassName?.isEmpty ?? true {
            warnings.append("View '\(view.id)' has no view class and can only be created via a factory")
        }
        if view.isModuleDefaultTab && (view.moduleId?.isEmpty ?? true) {
            warnings.append("View '\(view.id)' is a module default tab but has no moduleId")
        }
        if view.titleKey?.isEmpty ?? true {
            warnings.append("View '\(view.id)' has no titleKey; consider one for dynamic localization")
        }
        return ContributionValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }

    /// Validates a command id.
    public static func validateCommandId(_ commandId: String) -> ContributionValidationResult {
        if commandId.isEmpty { return .failure("Command id is required") }
        if !matches(commandId, menuCommandIdPattern) { return .failure("Command id '\(commandId)' has an invalid format") }
        return .success()
    }
}
