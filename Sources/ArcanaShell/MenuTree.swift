//
//  MenuTree.swift
//  ArcanaShell — builds a nested menu tree from the flat menu contributions.
//
//  Faithful to the Windows shell: the tree is built from `.mainMenu` roots plus `parentId`
//  links only (the File/Edit/View/... MenuLocation values are decorative grouping hints on
//  children, not separate roots).
//

import Foundation
import ArcanaPluginContracts

/// A node in the rendered menu tree.
public struct MenuNode: Identifiable, Sendable, Equatable {
    public let item: MenuItemDefinition
    public let children: [MenuNode]
    public var id: String { item.id }

    public init(item: MenuItemDefinition, children: [MenuNode] = []) {
        self.item = item
        self.children = children
    }

    public var isLeaf: Bool { children.isEmpty }
}

public enum MenuTree {
    /// Builds the main-menu tree: roots are top-level `.mainMenu` items (no parent), children
    /// hang off them by `parentId` regardless of their own (decorative) location, each level
    /// ordered by `order`.
    public static func build(from items: [MenuItemDefinition]) -> [MenuNode] {
        let roots = items
            .filter { $0.parentId == nil && $0.location == .mainMenu }
            .sorted { $0.order < $1.order }
        return roots.map { node(for: $0, all: items) }
    }

    private static func node(for item: MenuItemDefinition, all: [MenuItemDefinition]) -> MenuNode {
        let children = all
            .filter { $0.parentId == item.id }
            .sorted { $0.order < $1.order }
            .map { node(for: $0, all: all) }
        return MenuNode(item: item, children: children)
    }
}
