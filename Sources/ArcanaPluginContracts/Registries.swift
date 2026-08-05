//
//  Registries.swift
//  ArcanaPluginContracts — the menu / view / command registries plugins contribute to.
//  Ported from IMenuRegistry / IViewRegistry / CommandService.
//
//  These are `Sendable` services (the C# impls were ConcurrentDictionary + lock, not
//  UI-thread-bound); the SwiftUI desktop shell reads immutable snapshots from them.
//

import Foundation

/// Registry of contributed menu items, queryable by location.
public protocol MenuRegistry: Sendable {
    @discardableResult
    func registerMenuItem(_ item: MenuItemDefinition) -> any Disposable
    @discardableResult
    func registerMenuItems(_ items: [MenuItemDefinition]) -> any Disposable
    func menuItems(at location: MenuLocation) -> [MenuItemDefinition]
    func menuItems(at location: MenuLocation, moduleId: String) -> [MenuItemDefinition]
    func allMenuItems() -> [MenuItemDefinition]
}

/// Registry of contributed views, addressable by id.
public protocol ViewRegistry: Sendable {
    @discardableResult
    func registerView(_ view: ViewDefinition) -> any Disposable
    func view(id: String) -> ViewDefinition?
    func allViews() -> [ViewDefinition]
    func moduleDefaultTabs(moduleId: String) -> [ViewDefinition]
}

/// Registry + dispatcher of commands. A command is an async handler keyed by id.
public protocol CommandRegistry: Sendable {
    @discardableResult
    func registerCommand(_ commandId: String, _ handler: @escaping @Sendable () async -> Void) -> any Disposable
    @discardableResult
    func execute(_ commandId: String) async -> Bool
    func commands() -> [String]
    func hasCommand(_ commandId: String) -> Bool
}
