//
//  Contributions.swift
//  ArcanaPluginContracts — the contribution-point definitions plugins register
//  (menus, views, commands), ported from Arcana.Plugins.Contracts.
//

import Foundation

// MARK: - Menus

/// Where a menu item is contributed (12 locations, verbatim from the C# enum).
public enum MenuLocation: String, Sendable, Codable, CaseIterable {
    case mainMenu, fileMenu, editMenu, viewMenu, toolsMenu, helpMenu
    case contextMenu, toolbar, statusBar, functionTree, quickAccess, moduleQuickAccess
}

/// A contributed menu item. Items may nest (`children`) and may be conditionally shown (`when`).
public struct MenuItemDefinition: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let location: MenuLocation
    public let parentId: String?
    public let icon: String?
    public let tooltip: String?
    public let shortcut: String?
    public let command: String?
    public let order: Int
    public let group: String?
    public let when: String?
    public let isSeparator: Bool
    public let children: [MenuItemDefinition]
    public let moduleId: String?

    public init(
        id: String,
        title: String,
        location: MenuLocation,
        parentId: String? = nil,
        icon: String? = nil,
        tooltip: String? = nil,
        shortcut: String? = nil,
        command: String? = nil,
        order: Int = 0,
        group: String? = nil,
        when: String? = nil,
        isSeparator: Bool = false,
        children: [MenuItemDefinition] = [],
        moduleId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.location = location
        self.parentId = parentId
        self.icon = icon
        self.tooltip = tooltip
        self.shortcut = shortcut
        self.command = command
        self.order = order
        self.group = group
        self.when = when
        self.isSeparator = isSeparator
        self.children = children
        self.moduleId = moduleId
    }
}

// MARK: - Views

/// The kind of view a plugin contributes (5 types, verbatim from the C# enum).
public enum ViewType: String, Sendable, Codable, CaseIterable {
    case page, dialog, panel, widget, flyout
}

/// A contributed view. `viewClassName` names the SwiftUI view the host resolves via its
/// view factory (the Swift analogue of the C# `ViewClass`/`ViewClassName` reflection pair).
public struct ViewDefinition: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let titleKey: String?
    public let icon: String?
    public let type: ViewType
    public let viewClassName: String?
    public let canHaveMultipleInstances: Bool
    public let category: String?
    public let order: Int
    public let moduleId: String?
    public let isModuleDefaultTab: Bool
    public let moduleTabOrder: Int

    public init(
        id: String,
        title: String,
        titleKey: String? = nil,
        icon: String? = nil,
        type: ViewType = .page,
        viewClassName: String? = nil,
        canHaveMultipleInstances: Bool = false,
        category: String? = nil,
        order: Int = 0,
        moduleId: String? = nil,
        isModuleDefaultTab: Bool = false,
        moduleTabOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.titleKey = titleKey
        self.icon = icon
        self.type = type
        self.viewClassName = viewClassName
        self.canHaveMultipleInstances = canHaveMultipleInstances
        self.category = category
        self.order = order
        self.moduleId = moduleId
        self.isModuleDefaultTab = isModuleDefaultTab
        self.moduleTabOrder = moduleTabOrder
    }
}

// MARK: - Commands

/// A contributed command descriptor.
public struct CommandDefinition: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let category: String?
    public let icon: String?
    public let tooltip: String?
    public let shortcut: String?
    public let when: String?

    public init(
        id: String,
        title: String,
        category: String? = nil,
        icon: String? = nil,
        tooltip: String? = nil,
        shortcut: String? = nil,
        when: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.icon = icon
        self.tooltip = tooltip
        self.shortcut = shortcut
        self.when = when
    }
}
