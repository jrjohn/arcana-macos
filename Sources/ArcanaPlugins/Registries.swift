//
//  Registries.swift
//  ArcanaPlugins — in-memory implementations of the menu / view / command registries.
//  Lock-guarded (the C# impls used ConcurrentDictionary + lock) and `Sendable`.
//

import Foundation
import ArcanaPluginContracts

/// In-memory menu registry. Items are keyed by id; queries filter by location and sort by order.
public final class MenuRegistryImpl: MenuRegistry, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: MenuItemDefinition] = [:]

    public init() {}

    @discardableResult
    public func registerMenuItem(_ item: MenuItemDefinition) -> any Disposable {
        lock.lock(); items[item.id] = item; lock.unlock()
        return CallbackDisposable { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.items[item.id] = nil; self.lock.unlock()
        }
    }

    @discardableResult
    public func registerMenuItems(_ list: [MenuItemDefinition]) -> any Disposable {
        let tokens = list.map { registerMenuItem($0) }
        return CallbackDisposable { tokens.forEach { $0.dispose() } }
    }

    public func menuItems(at location: MenuLocation) -> [MenuItemDefinition] {
        snapshot().filter { $0.location == location }.sorted { $0.order < $1.order }
    }

    public func menuItems(at location: MenuLocation, moduleId: String) -> [MenuItemDefinition] {
        menuItems(at: location).filter { $0.moduleId == moduleId }
    }

    public func allMenuItems() -> [MenuItemDefinition] {
        snapshot().sorted { $0.order < $1.order }
    }

    private func snapshot() -> [MenuItemDefinition] {
        lock.lock(); defer { lock.unlock() }
        return Array(items.values)
    }
}

/// In-memory view registry, addressable by id.
public final class ViewRegistryImpl: ViewRegistry, @unchecked Sendable {
    private let lock = NSLock()
    private var views: [String: ViewDefinition] = [:]

    public init() {}

    @discardableResult
    public func registerView(_ view: ViewDefinition) -> any Disposable {
        lock.lock(); views[view.id] = view; lock.unlock()
        return CallbackDisposable { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.views[view.id] = nil; self.lock.unlock()
        }
    }

    public func view(id: String) -> ViewDefinition? {
        lock.lock(); defer { lock.unlock() }
        return views[id]
    }

    public func allViews() -> [ViewDefinition] {
        lock.lock(); defer { lock.unlock() }
        return Array(views.values).sorted { $0.order < $1.order }
    }

    public func moduleDefaultTabs(moduleId: String) -> [ViewDefinition] {
        allViews().filter { $0.moduleId == moduleId && $0.isModuleDefaultTab }
            .sorted { $0.moduleTabOrder < $1.moduleTabOrder }
    }
}

/// In-memory command registry + async dispatcher, keyed by command id.
public final class CommandRegistryImpl: CommandRegistry, @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [String: @Sendable () async -> Void] = [:]

    public init() {}

    @discardableResult
    public func registerCommand(
        _ commandId: String, _ handler: @escaping @Sendable () async -> Void
    ) -> any Disposable {
        lock.lock(); handlers[commandId] = handler; lock.unlock()
        return CallbackDisposable { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.handlers[commandId] = nil; self.lock.unlock()
        }
    }

    @discardableResult
    public func execute(_ commandId: String) async -> Bool {
        // Snapshot under the lock in a synchronous helper — NSLock must not be held across
        // an `await` (and Swift 6 forbids calling it from an async context at all).
        guard let handler = handler(for: commandId) else { return false }
        await handler()
        return true
    }

    private func handler(for commandId: String) -> (@Sendable () async -> Void)? {
        lock.lock(); defer { lock.unlock() }
        return handlers[commandId]
    }

    public func commands() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(handlers.keys)
    }

    public func hasCommand(_ commandId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return handlers[commandId] != nil
    }
}
